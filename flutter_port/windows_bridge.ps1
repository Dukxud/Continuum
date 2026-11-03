# Flutter Windows adapter. JSON-in/JSON-out; no UI globals or shared server.
# The existing verified worker owns all execution and account safety checks.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('load','pending','usage','select','schedule','cancel','evidence','hide','save','browse')][string]$Action,
    [string]$Payload = ''
)
$ErrorActionPreference='Stop'
try {
    $source=Split-Path -Parent $PSScriptRoot
    $appDir=Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
    $request=if($Payload){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload)) | ConvertFrom-Json -ErrorAction Stop}else{[pscustomobject]@{}}
    $null=. (Join-Path $source 'CodexRunEngine.ps1')
    $null=. (Join-Path $source 'CodexData.ps1')
    $result=$null
    switch($Action){
        'load' {
            $result=@{
                sessions=@(Get-RecentCliSessions)
                pending=@(Get-UpcomingCodexTasks -AppDirectory $appDir)
                history=@(Get-CodexRunHistory -Directory $appDir -Limit 100)
                settings=Read-CodexUiSettings $appDir
                logDirectory=$appDir
            }
        }
        'pending' {
            $result=@{
                pending=@(Get-UpcomingCodexTasks -AppDirectory $appDir)
                history=@(Get-CodexRunHistory -Directory $appDir -Limit 100)
            }
        }
        'usage' {
            $model=[string]$request.model
            if($model -and $model -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$'){throw 'Invalid model identifier.'}
            $helper=Join-Path $source 'CodexUsage.js'
            $cli=Get-CodexCliJs
            $arguments=@($helper,'--cli-js',$cli)
            if($model){$arguments+=@('--model',$model)}
            $lines=@(& node.exe @arguments)
            if($LASTEXITCODE -ne 0 -or -not $lines){throw 'Codex account and model query failed.'}
            $snapshot=($lines | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
            if(-not $snapshot.ok){throw "Codex usage unavailable: $($snapshot.error)"}
            $result=$snapshot
        }
        'select' {
            $id=[string]$request.sessionId
            $session=@(Get-RecentCliSessions | Where-Object { $_.Id -ceq $id }) | Select-Object -First 1
            if(-not $session){throw 'Selected CLI conversation could not be verified.'}
            $cwd=Get-ReportedThreadDirectory -SessionId $id -SourceFolder $source
            $found=Find-SessionRepository -Session $session -ReportedCwd $cwd -AppDirectory $appDir
            $result=@{sessionId=$id;model=Read-SessionModel $session;found=$found}
        }
        'schedule' {
            $sessionId=[string]$request.sessionId
            if($sessionId -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'){throw 'Invalid session ID.'}
            if(-not @(Get-RecentCliSessions | Where-Object { $_.Id -ceq $sessionId }).Count){throw 'Selected CLI session not verified.'}
            $root=Get-RepositoryRoot ([string]$request.repo).Trim().Trim('"')
            if(-not $root){throw 'Choose an existing Git repository.'}
            $branchName=Get-RepositoryBranch $root
            $when=[datetime]::MinValue
            if(-not [datetime]::TryParseExact([string]$request.runAt,'yyyy-MM-ddTHH:mm:ss',
                    [Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$when)){
                throw 'Invalid local run time.'
            }
            if($when -lt (Get-Date).AddSeconds(30)){throw 'Choose a time at least 30 seconds ahead.'}
            if([TimeZoneInfo]::Local.IsAmbiguousTime($when) -or [TimeZoneInfo]::Local.IsInvalidTime($when)){
                throw 'Run time is ambiguous or nonexistent due to daylight saving time.'
            }
            $model=[string]$request.model
            $effort=[string]$request.effort
            if($model -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$'){throw 'Invalid model.'}
            if($effort -cnotmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,40}$'){throw 'Invalid reasoning effort.'}
            $access=[string]$request.access
            if($access -cnotin @('workspace-write','read-only','yolo')){throw 'Invalid access mode.'}
            if($access -eq 'yolo' -and $request.confirmUnrestricted -ne $true){throw 'Explicit unrestricted-access confirmation required.'}
            $message=([string]$request.message).Trim()
            if(-not $message){throw 'Enter an instruction.'}
            # Register only with a fresh model-specific catalog and verified workspace.
            $helper=Join-Path $source 'CodexUsage.js'
            $cli=Get-CodexCliJs
            $lines=@(& node.exe $helper --cli-js $cli --model $model)
            if($LASTEXITCODE -ne 0 -or -not $lines){throw 'Live Codex account verification failed.'}
            $usage=($lines | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
            if(-not $usage.ok -or $usage.catalogError){throw 'Live model catalog or quota unavailable; scheduling is disabled.'}
            Assert-ModelEffortSupported -Models @($usage.models) -Model $model -Effort $effort
            if($usage.model -cne $model){throw 'Quota response does not match the chosen model.'}
            if(-not (Test-CanonicalWorkspaceIdentity ([string]$usage.accountId))){throw 'Workspace identity could not be verified.'}
            if($usage.ordinaryUsageAllowed -eq $false){throw 'Codex quota is currently restricted. No task was registered.'}
            $upcoming=@(Get-UpcomingCodexTasks -AppDirectory $appDir | Where-Object { $_.Status -in @('Running','Scheduled') })
            if(@($upcoming | Where-Object {$_.Status -eq 'Running' -and $_.Session -ceq $sessionId}).Count){
                throw 'This conversation is already running in a Scheduler worker.'
            }
            $overlap=@($upcoming | Where-Object { $_.Repo -ne '-' -and $_.Repo.TrimEnd([char[]]@('/','\')) -ieq $root.TrimEnd([char[]]@('/','\')) })
            if($overlap.Count -gt 0 -and $request.confirmOverlap -ne $true){
                throw "Repository has $($overlap.Count) upcoming job(s). Confirm possible overlap first."
            }
            [void](New-Item -Path $appDir -ItemType Directory -Force)
            $runtime=Publish-ImmutableRuntime -SourceDirectory $source -DestinationDirectory (Join-Path $appDir 'runtimes') -RelativeFiles (Get-CodexRuntimeFiles)
            $name='CodexResume-' + $when.ToString('yyyyMMdd-HHmm') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
            $jobFilePath=Join-Path $appDir ($name+'.json')
            $log=Join-Path $appDir ($name+'.log')
            [pscustomobject]@{
                sessionId=$sessionId;repo=$root;branch=$branchName;model=$model
                effort=$effort;access=$access;message=$message
                createdAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                accountId=[string]$usage.accountId;runtimeFingerprint=$runtime.Fingerprint;log=$log
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jobFilePath -Encoding utf8
            $runner=Join-Path $runtime.Directory 'CodexRunJob.vbs'
            $arguments=Get-CodexTaskArguments -Runner $runner -JobFile $jobFilePath
            try {
                [void](Register-OneTimeTask -Name $name -At $when -Executable (Join-Path $env:WINDIR 'System32\wscript.exe') -Arguments $arguments -WorkingDirectory $root -Description "Codex session $sessionId ($branchName)")
            }catch{
                if(-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)){
                    Remove-Item -LiteralPath $jobFilePath -Force -ErrorAction SilentlyContinue
                }
                throw
            }
            $result=@{name=$name;status='Scheduled'}
        }
        'cancel' {
            $name=[string]$request.name
            if($name -cnotmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}$'){throw 'Invalid Scheduler task name.'}
            Remove-OneTimeTask -Name $name -OnlyBeforeStart
            $warning=''
            $payloadPath=Join-Path $appDir ($name+'.json')
            if(Test-Path -LiteralPath $payloadPath -PathType Leaf){
                try {
                    [void](Write-JobOutcome -Path ([IO.Path]::ChangeExtension($payloadPath,'.result.json')) -Status 'cancelled' -Message 'Cancelled by operator before execution.')
                    Remove-Item -LiteralPath $payloadPath -Force -ErrorAction Stop
                }catch{$warning=$_.Exception.Message}
            }
            $result=@{name=$name;status='Cancelled';warning=$warning}
        }
        'evidence' {
            $name=[string]$request.name
            if($name -cnotmatch '^(?:CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}|BP[0-9]+-Codex-(?:Resume|Test))$'){
                throw 'Invalid history identifier.'
            }
            $result=Get-CodexRunEvidence -Directory $appDir -Name $name
        }
        'hide' {
            $name=[string]$request.name
            Hide-CodexRunRecord -Directory $appDir -Name $name
            $result=@{hidden=$name}
        }
        'save' {
            $draft=$request.draft
            if(-not $draft){throw 'No draft supplied.'}
            $access=[string]$draft.access
            if($access -cnotin @('workspace-write','read-only','yolo')){throw 'Invalid access mode.'}
            $previous=Read-CodexUiSettings $appDir
            $safeDraft=[pscustomobject]@{
                sessionId=[string]$draft.sessionId;repo=[string]$draft.repo
                model=[string]$draft.model;effort=[string]$draft.effort
                access=$access;message=[string]$draft.message;runAt=[string]$draft.runAt
            }
            $settings=[pscustomobject]@{
                version=1;lastAccess=$access
                compactMode=($request.compactMode -eq $true)
                barAppearance=$(if($previous){$previous.barAppearance}else{$null})
                flutterAppearance=$(if($request.flutterAppearance){$request.flutterAppearance}elseif($previous){$previous.flutterAppearance}else{$null})
                draft=$safeDraft
            }
            Write-CodexUiSettings -Directory $appDir -State $settings
            $result=@{saved=$true}
        }
        'browse' {
            Add-Type -AssemblyName System.Windows.Forms
            $dialog=[Windows.Forms.FolderBrowserDialog]::new()
            $dialog.Description='Select the Git repository for this conversation'
            try {
                $result=if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
                    @{path=[string]$dialog.SelectedPath}
                }else{@{path=''}}
            }finally{$dialog.Dispose()}
        }
    }
    [Console]::Out.WriteLine((@{ok=$true;result=$result} | ConvertTo-Json -Depth 20 -Compress))
} catch {
    [Console]::Out.WriteLine((@{ok=$false;error=$_.Exception.Message} | ConvertTo-Json -Depth 6 -Compress))
    exit 1
}
