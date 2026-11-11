# Codex-specific quota continuations. No UI, timers, or uncontrolled retries.
# The calling pinned worker owns execution, workspace verification and outcomes.
Import-Module (Join-Path $PSScriptRoot '../../components/SettingsStore/SettingsStore.psm1') -ErrorAction Stop

function Test-CodexContinuationPolicy {
    param($Job)
    $p=$Job.continuationPolicy
    if(-not $p -or [string]$p.mode -cne 'quota-only' -or
       [string]$p.schema -cne '1' -or [string]$p.maxContinuations -cne '3'){return $false}
    $attempt=[string]$Job.retryAttempt
    return ($attempt -cmatch '^[0-3]$')
}

# Only terminal structured Codex events authorize a post-run quota deferral.
# Human text and agent messages are deliberately not error evidence.
function Test-CodexTerminalQuotaFailure {
    param([Parameter(Mandatory)][string]$EventsPath)
    if(-not (Test-Path -LiteralPath $EventsPath -PathType Leaf)){return $false}
    $terminal=$null
    foreach($line in @(Get-Content -LiteralPath $EventsPath -Tail 128 -ErrorAction Stop)){
        if(-not $line.TrimStart().StartsWith('{')){continue}
        try{$event=$line | ConvertFrom-Json -ErrorAction Stop}catch{continue}
        if($event.type -in @('turn.completed','turn.failed')){$terminal=$event}
    }
    if(-not $terminal -or [string]$terminal.type -cne 'turn.failed'){return $false}
    $reason=[string]$terminal.error.message
    # A trailing stderr cleanup error is not proof that the saved thread is gone.
    # The worker independently verifies thread/read before registering a child.
    return ($reason -match '(?i)(?:usage|rate)[ -]?limit|quota (?:exceeded|exhausted)' -and
            $reason -notmatch '(?i)thread.{0,100}not found|thread-store conflict|already has an active writer')
}

# Reset comes from the model-matched App Server rate-limits result, never from
# CLI prose. DateTimeOffset conversion keeps source seconds and DST boundaries.
function Get-VerifiedQuotaContinuationTime {
    param($Quota,[string]$AccountId,[string]$Model,[datetimeoffset]$Now=[DateTimeOffset]::UtcNow)
    if(-not $Quota -or $Quota.ok -ne $true -or
       [string]$Quota.model -cne $Model -or $Quota.selectionVerified -ne $true -or
       [string]$Quota.accountId -cne $AccountId -or
       $Quota.canAttempt -ne $false -or
       [string]$Quota.recommendationKind -cne 'exhausted-window'){return $null}
    $value=[string]$Quota.recommendedResetAt
    if($value -cnotmatch '^[0-9]{10,11}$'){return $null}
    try {
        $reset=[DateTimeOffset]::FromUnixTimeSeconds([long]$value)
        if($reset -le $Now -or $reset -gt $Now.AddDays(14)){return $null}
        $at=$reset.AddMinutes(1).ToLocalTime().DateTime
        if([TimeZoneInfo]::Local.IsInvalidTime($at) -or
           [TimeZoneInfo]::Local.IsAmbiguousTime($at)){return $null}
        return $at
    }catch{return $null}
}

function Assert-NoPendingCodexSessionSibling {
    param([string]$SessionId,[string]$ParentName,[string]$Directory)
    foreach($task in @(Get-ScheduledTask -TaskName 'CodexResume-*' -ErrorAction SilentlyContinue)){
        $name=[string]$task.TaskName
        if($name -ceq $ParentName -or
           $name -cnotmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[a-fA-F0-9]{8}$' -or
           $task.State -ne 'Ready'){continue}
        $trigger=@($task.Triggers | Where-Object {$_.StartBoundary}) | Select-Object -First 1
        if(-not $trigger){continue}
        try{if([datetime]$trigger.StartBoundary -le (Get-Date)){continue}}
        catch{continue}
        $sibling=SettingsStore\Read-JsonSettings -Path (Join-Path $Directory ($name+'.json'))
        if($sibling -and [string]$sibling.sessionId -ceq $SessionId){
            throw "Another future continuation already targets this conversation ($name)."
        }
    }
}

function Get-CodexQuotaContinuationMessage {
    param([string]$OriginalMessage)
    return 'Previous work stopped at a verified Codex usage limit. Inspect this conversation and the repository state; do not repeat completed changes or external side effects. Continue only unfinished work from the original instruction: '+$OriginalMessage
}

function Get-RegisteredCodexQuotaContinuation {
    param($Job,[string]$JobFile,[string]$Directory,[string]$RuntimeDirectory)
    $parent=[IO.Path]::GetFileNameWithoutExtension($JobFile)
    $planPath=Join-Path $Directory ($parent+'.continuation.json')
    if(-not (Test-Path -LiteralPath $planPath -PathType Leaf)){return $null}
    $plan=SettingsStore\Read-JsonSettings -Path $planPath
    if(-not $plan -or [string]$plan.parentJob -cne $parent -or
       [string]$plan.nextJob -cnotmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[a-fA-F0-9]{8}$'){
        throw 'Existing continuation intent is unreadable or mismatched; manual review required.'
    }
    $name=[string]$plan.nextJob
    $task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if(-not $task -or $task.State -notin @('Ready','Running')){
        throw 'Continuation intent exists but the Windows task is absent or disabled; no automatic replacement.'
    }
    $payload=SettingsStore\Read-JsonSettings -Path (Join-Path $Directory ($name+'.json'))
    if(-not $payload -or [string]$payload.parentJob -cne $parent -or
       [string]$payload.sessionId -cne [string]$Job.sessionId -or
       [string]$payload.accountId -cne [string]$Job.accountId -or
       [string]$payload.runtimeFingerprint -cne [string]$Job.runtimeFingerprint -or
       [string]$payload.repo -cne [string]$Job.repo -or
       [string]$payload.branch -cne [string]$Job.branch -or
       [string]$payload.model -cne [string]$Job.model -or
       [string]$payload.effort -cne [string]$Job.effort -or
       [string]$payload.access -cne [string]$Job.access -or
       [string]$payload.retryAttempt -cne [string]([int]$Job.retryAttempt+1)){
        throw 'Registered child does not preserve its parent identity and attempt; no duplicate.'
    }
    $rootJob=if($Job.rootJob){[string]$Job.rootJob}else{$parent}
    $original=if($Job.originalMessage){[string]$Job.originalMessage}else{[string]$Job.message}
    if([string]$payload.rootJob -cne $rootJob -or
       [string]$payload.originalMessage -cne $original -or
       [string]$payload.message -cne (Get-CodexQuotaContinuationMessage $original) -or
       [string]$payload.log -cne (Join-Path $Directory ($name+'.log')) -or
       -not (Test-CodexContinuationPolicy $payload)){
        throw 'Registered child instruction, policy or provenance differs from its parent.'
    }
    # Validate the *actual* Task Scheduler executable, arguments, working
    # directory and single trigger, not merely a matching task name.
    try {
        $planned=[datetime]$plan.when
        if(@($task.Triggers).Count -ne 1 -or
           [datetime]$task.Triggers[0].StartBoundary -ne $planned){
            throw 'Windows trigger does not match saved plan.'
        }
        $action=@($task.Actions)
        $expectedRunner=Join-Path $RuntimeDirectory 'src/backend/CodexRunJob.vbs'
        $expectedArguments=Get-CodexTaskArguments -Runner $expectedRunner -JobFile (Join-Path $Directory ($name+'.json'))
        if($action.Count -ne 1 -or
           [string]$action[0].Execute -ine (Join-Path $env:WINDIR 'System32\wscript.exe') -or
           [string]$action[0].Arguments -cne $expectedArguments -or
           [string]$action[0].WorkingDirectory -ine [string]$Job.repo){
            throw 'Windows action does not match the pinned continuation.'
        }
    }catch{throw "Registered child task cannot be verified; manual review required: $($_.Exception.Message)"}
    return [pscustomobject]@{Name=$name;When=$planned}
}

# Intent is saved before the OS task. A registration failure is not
# automatically retried, preventing duplicate jobs or unexpected side effects.
function Register-CodexQuotaContinuation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Job,
        [Parameter(Mandatory)][string]$JobFile,
        [Parameter(Mandatory)][string]$AppDirectory,
        [Parameter(Mandatory)][string]$RuntimeDirectory,
        [datetime]$When=[datetime]::MinValue
    )
    if(-not (Test-CodexContinuationPolicy $Job)){throw 'Quota continuation was not authorized.'}
    $attempt=[int]$Job.retryAttempt
    if($attempt -ge 3){throw 'Automatic continuation limit reached.'}
    $parent=[IO.Path]::GetFileNameWithoutExtension($JobFile)
    if($parent -cnotmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[a-fA-F0-9]{8}$'){
        throw 'Only verified Scheduler jobs may create a continuation.'
    }
    $existing=Get-RegisteredCodexQuotaContinuation -Job $Job -JobFile $JobFile -Directory $AppDirectory -RuntimeDirectory $RuntimeDirectory
    if($existing){return $existing}
    if($When -le (Get-Date).AddSeconds(60)){throw 'No safely scheduled continuation time was provided.'}
    Assert-NoPendingCodexSessionSibling -SessionId ([string]$Job.sessionId) -ParentName $parent -Directory $AppDirectory
    $nextAttempt=$attempt+1
    $digest=[Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($parent + ':' + $nextAttempt))
    $token=[Convert]::ToHexString($digest).Substring(0,8).ToLowerInvariant()
    $name='CodexResume-'+$When.ToString('yyyyMMdd-HHmm')+'-'+$token
    $planPath=Join-Path $AppDirectory ($parent+'.continuation.json')
    $nextJobPath=Join-Path $AppDirectory ($name+'.json')
    if(Test-Path -LiteralPath $nextJobPath){throw 'Existing continuation payload requires manual review.'}
    $rootJob=if($Job.rootJob){[string]$Job.rootJob}else{$parent}
    $rootMessage=if($Job.originalMessage){[string]$Job.originalMessage}else{[string]$Job.message}
    $continuationText=Get-CodexQuotaContinuationMessage $rootMessage
    $child=[ordered]@{
        sessionId=[string]$Job.sessionId;repo=[string]$Job.repo;branch=[string]$Job.branch
        model=[string]$Job.model;effort=[string]$Job.effort;access=[string]$Job.access
        message=$continuationText;originalMessage=$rootMessage
        createdAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        accountId=[string]$Job.accountId;runtimeFingerprint=[string]$Job.runtimeFingerprint
        log=(Join-Path $AppDirectory ($name+'.log'))
        continuationPolicy=@{schema=1;mode='quota-only';maxContinuations=3}
        retryAttempt=$nextAttempt;parentJob=$parent;rootJob=$rootJob
    }
    $plan=[ordered]@{schema=1;parentJob=$parent;nextJob=$name;when=$When.ToString('o')}
    SettingsStore\Write-JsonSettings -Path $planPath -Value $plan
    SettingsStore\Write-JsonSettings -Path $nextJobPath -Value $child
    $runner=Join-Path $RuntimeDirectory 'src/backend/CodexRunJob.vbs'
    $arguments=Get-CodexTaskArguments -Runner $runner -JobFile $nextJobPath
    [void](Register-OneTimeTask -Name $name -At $When -Executable (Join-Path $env:WINDIR 'System32\wscript.exe') -Arguments $arguments -WorkingDirectory ([string]$Job.repo) -Description "Codex quota continuation $nextAttempt of 3 ($parent)")
    return [pscustomobject]@{Name=$name;When=$When}
}
