# Request validation and one-time registration. Execution belongs to the pinned backend worker.

function Register-FlutterSchedule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Request,
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    if($null -ne $Request.autoResumeOnLimit -and $Request.autoResumeOnLimit -isnot [bool]){throw 'Invalid automatic-continuation option.'}
    $executionMode=if($Request.executionMode){[string]$Request.executionMode}else{'background'}
    if($executionMode -cnotin @('terminal','background','shared')){throw 'Invalid execution mode.'}
    if($executionMode -in @('terminal','shared') -and $Request.autoResumeOnLimit -eq $true){
        throw 'Automatic quota continuation requires Background execution.'
    }
    $sessionId=[string]$Request.sessionId
    if($sessionId -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'){throw 'Invalid session ID.'}
    # Validate the actual Flutter wall-clock value before any lookup or
    # mutation. Reject UTC/offset inputs, which are not local times.
    $when=[datetime]::MinValue
    $runAt=$Request.runAt
    if($runAt -is [datetime]){
        if($runAt.Kind -ne [DateTimeKind]::Unspecified){throw 'Invalid local run time.'}
        $when=$runAt
    }elseif($runAt -isnot [string] -or -not [datetime]::TryParseExact(
            $runAt,'yyyy-MM-ddTHH:mm:ss',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,[ref]$when)){
        throw 'Invalid local run time.'
    }
    if($when -lt (Get-Date).AddSeconds(30)){throw 'Choose a time at least 30 seconds ahead.'}
    if([TimeZoneInfo]::Local.IsAmbiguousTime($when) -or [TimeZoneInfo]::Local.IsInvalidTime($when)){
        throw 'Run time is ambiguous or nonexistent due to daylight saving time.'
    }
    if(-not @(Get-RecentCliSessions | Where-Object { $_.Id -ceq $sessionId }).Count){throw 'Selected CLI session not verified.'}
    $root=Get-RepositoryRoot ([string]$Request.repo).Trim().Trim('"')
    if(-not $root){throw 'Choose an existing Git repository.'}
    $branchName=Get-RepositoryBranch $root
    $model=[string]$Request.model
    $effort=[string]$Request.effort
    if($model -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$'){throw 'Invalid model.'}
    if($effort -cnotmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,40}$'){throw 'Invalid reasoning effort.'}
    $access=[string]$Request.access
    if($access -cnotin @('workspace-write','read-only','yolo')){throw 'Invalid access mode.'}
    if($access -eq 'yolo' -and $Request.confirmUnrestricted -ne $true){throw 'Explicit unrestricted-access confirmation required.'}
    $policy=if($Request.autoResumeOnLimit -eq $true){
        @{schema=1;mode='quota-only';maxContinuations=3}
    }else{$null}
    $message=([string]$Request.message).Trim()
    if(-not $message){throw 'Enter an instruction.'}
    # Register only with a fresh model-specific catalog and verified workspace.
    $helper=Join-Path $SourceDirectory 'src/backend/CodexUsage.js'
    $cli=Get-CodexCliJs
    $lines=@(& node.exe $helper --cli-js $cli --model $model)
    if($LASTEXITCODE -ne 0 -or -not $lines){throw 'Live Codex account verification failed.'}
    $usage=($lines | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if(-not $usage.ok -or $usage.catalogError){throw 'Live model catalog or quota unavailable; scheduling is disabled.'}
    Assert-ModelEffortSupported -Models @($usage.models) -Model $model -Effort $effort
    if($usage.model -cne $model){throw 'Quota response does not match the chosen model.'}
    if(-not (Test-CanonicalWorkspaceIdentity ([string]$usage.accountId))){throw 'Workspace identity could not be verified.'}
    # Matching WinForms v1.16: a future task may be registered while
    # current quota is exhausted. The pinned worker independently
    # fails closed if quota is still unavailable at execution time.
    $upcoming=@(Get-UpcomingCodexTasks -AppDirectory $AppDirectory | Where-Object { $_.Status -in @('Running','Scheduled') })
    if(@($upcoming | Where-Object {$_.Status -eq 'Running' -and $_.Session -ceq $sessionId}).Count){
        throw 'This conversation is already running in a Scheduler worker.'
    }
    $overlap=@($upcoming | Where-Object { $_.Repo -ne '-' -and $_.Repo.TrimEnd([char[]]@('/','\')) -ieq $root.TrimEnd([char[]]@('/','\')) })
    if($overlap.Count -gt 0 -and $Request.confirmOverlap -ne $true){
        throw "Repository has $($overlap.Count) upcoming job(s). Confirm possible overlap first."
    }
    [void](New-Item -Path $AppDirectory -ItemType Directory -Force)
    $runtime=Publish-ImmutableRuntime -SourceDirectory $SourceDirectory -DestinationDirectory (Join-Path $AppDirectory 'runtimes') -RelativeFiles (Get-CodexRuntimeFiles)
    $name='CodexResume-' + $when.ToString('yyyyMMdd-HHmm') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
    $jobFilePath=Join-Path $AppDirectory ($name+'.json')
    $log=Join-Path $AppDirectory ($name+'.log')
    [pscustomobject]@{
        sessionId=$sessionId;repo=$root;branch=$branchName;model=$model
        effort=$effort;access=$access;message=$message
        executionMode=$executionMode
        continuationPolicy=$policy;retryAttempt=0
        createdAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        accountId=[string]$usage.accountId;runtimeFingerprint=$runtime.Fingerprint;log=$log
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jobFilePath -Encoding utf8
    $runner=Join-Path $runtime.Directory 'src/backend/CodexRunJob.vbs'
    $arguments=Get-CodexTaskArguments -Runner $runner -JobFile $jobFilePath -ExecutionMode $executionMode
    try {
        [void](Register-OneTimeTask -Name $name -At $when -Executable (Join-Path $env:WINDIR 'System32\wscript.exe') -Arguments $arguments -WorkingDirectory $root -Description "Codex session $sessionId ($branchName)")
    }catch{
        if(-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)){
            Remove-Item -LiteralPath $jobFilePath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    return @{name=$name;status='Scheduled'}
}
