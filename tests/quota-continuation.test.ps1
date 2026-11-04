# Isolated quota-continuation contract tests: no real Codex or Task Scheduler.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexRunEngine.ps1')
function Require($ok,[string]$message){if(-not $ok){throw $message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('quota-policy-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp -Force)

try {
    $events=Join-Path $temp 'events.jsonl'
    '{"type":"turn.failed","error":{"message":"You have hit your usage limit. Try again at a later time."}}' | Set-Content -LiteralPath $events
    Require (Test-CodexTerminalQuotaFailure -EventsPath $events) 'Terminal structured usage-limit error not detected.'
    @('{"type":"turn.failed","error":{"message":"Usage limit exceeded"}}',
      '{"type":"turn.completed"}') | Set-Content -LiteralPath $events
    Require (-not (Test-CodexTerminalQuotaFailure -EventsPath $events)) 'Successful terminal event must veto stale quota error.'
    @('{"type":"agent_message","text":"Usage limit exceeded"}',
      '{"type":"turn.failed","error":{"message":"Network disconnect"}}') | Set-Content -LiteralPath $events
    Require (-not (Test-CodexTerminalQuotaFailure -EventsPath $events)) 'Generic failure or agent text must not trigger quota retry.'
    # Exact BP169 ordering: terminal quota event followed by the rollout
    # recorder's secondary stderr. Worker thread/read must decide recoverability.
    @('{"type":"error","message":"You\u2019ve hit your usage limit. Try again at Nov 8th, 2026 9:58 AM."}',
      '{"type":"turn.failed","error":{"message":"You\u2019ve hit your usage limit. Try again at Nov 8th, 2026 9:58 AM."}}',
      '2026-11-04T21:20:52Z ERROR codex_core::session: failed to record rollout items: thread 00000000-0000-0000-0000-000000000001 not found') | Set-Content -LiteralPath $events
    Require (Test-CodexTerminalQuotaFailure -EventsPath $events) 'BP169 quota failure should reach authoritative thread verification.'
    '{"type":"turn.failed","error":{"message":"Usage limit; thread 00000000-0000-0000-0000-000000000001 not found"}}' | Set-Content -LiteralPath $events
    Require (-not (Test-CodexTerminalQuotaFailure -EventsPath $events)) 'Structured missing-thread failure must veto automatic continuation.'
    '{"type":"turn.failed","error":{"message":"thread-store conflict: already has an active writer"}}' | Set-Content -LiteralPath $events
    Require (-not (Test-CodexTerminalQuotaFailure -EventsPath $events)) 'Active writer must not be retried.'
    '{"type":"turn.failed","error":{"message":"Usage limit reached"}}' | Set-Content -LiteralPath $events

    $now=[DateTimeOffset]::Parse('2026-11-04T15:22:07-06:00')
    $epoch=$now.AddDays(4).AddHours(2).AddSeconds(30).ToUnixTimeSeconds()
    $account='workspace-sha256:'+('a'*64)
    $quota=[pscustomobject]@{
        ok=$true;model='test-model';selectionVerified=$true;accountId=$account
        canAttempt=$false;recommendationKind='exhausted-window';recommendedResetAt=$epoch
    }
    $when=Get-VerifiedQuotaContinuationTime -Quota $quota -AccountId $account -Model 'test-model' -Now $now
    $expected=[DateTimeOffset]::FromUnixTimeSeconds($epoch).AddMinutes(1).ToLocalTime().DateTime
    Require ($when -eq $expected) 'Verified reset + one minute must preserve exact seconds.'
    Require ($null -eq (Get-VerifiedQuotaContinuationTime -Quota $quota -AccountId 'wrong' -Model 'test-model' -Now $now)) 'Workspace mismatch accepted.'
    Require ($null -eq (Get-VerifiedQuotaContinuationTime -Quota $quota -AccountId $account -Model 'wrong-model' -Now $now)) 'Model mismatch accepted.'
    $quota.selectionVerified=$false
    Require ($null -eq (Get-VerifiedQuotaContinuationTime -Quota $quota -AccountId $account -Model 'test-model' -Now $now)) 'Unverified bucket accepted.'
    $quota.selectionVerified=$true
    $quota.recommendationKind='next-window'
    Require ($null -eq (Get-VerifiedQuotaContinuationTime -Quota $quota -AccountId $account -Model 'test-model' -Now $now)) 'Informational reset accepted.'
    $quota.recommendationKind='exhausted-window'
    $quota.canAttempt=$true
    Require ($null -eq (Get-VerifiedQuotaContinuationTime -Quota $quota -AccountId $account -Model 'test-model' -Now $now)) 'Available quota caused a retry.'
    $quota.canAttempt=$false
    $quota.recommendedResetAt=$now.AddDays(15).ToUnixTimeSeconds()
    Require ($null -eq (Get-VerifiedQuotaContinuationTime -Quota $quota -AccountId $account -Model 'test-model' -Now $now)) 'Unbounded reset accepted.'
    $quota.recommendedResetAt=$now.AddSeconds(-1).ToUnixTimeSeconds()
    Require ($null -eq (Get-VerifiedQuotaContinuationTime -Quota $quota -AccountId $account -Model 'test-model' -Now $now)) 'Past reset accepted.'
    $quota.recommendedResetAt=$epoch

    $job=[pscustomobject]@{
        sessionId='00000000-0000-0000-0000-000000000001'
        repo=$temp;branch='main';model='test-model';effort='high'
        access='read-only';message='Resume original work.';accountId=$account
        runtimeFingerprint=('b'*64);retryAttempt=0
        continuationPolicy=[pscustomobject]@{schema=1;mode='quota-only';maxContinuations=3}
    }
    Require (Test-CodexContinuationPolicy $job) 'Explicit versioned policy rejected.'
    $legacy=[pscustomobject]@{autoResume=$true;retryAttempt=0}
    Require (-not (Test-CodexContinuationPolicy $legacy)) 'Legacy autoResume field was reactivated.'
    $job.continuationPolicy.mode='all-failures'
    Require (-not (Test-CodexContinuationPolicy $job)) 'Unrestricted retry policy accepted.'
    $job.continuationPolicy.mode='quota-only'

    $script:threadAvailable=$true
    $script:threadChecks=0
    function Assert-CodexConversationAvailable {
        param([string]$SessionId)
        $script:threadChecks++
        if(-not $script:threadAvailable -or $SessionId -cne '00000000-0000-0000-0000-000000000001'){
            throw 'Codex thread/read failed.'
        }
    }

    $script:taskMap=@{}
    function global:Get-ScheduledTask {
        [CmdletBinding()]
        param([string]$TaskName)
        if($TaskName -eq 'CodexResume-*'){return @($script:taskMap.Values)}
        if($script:taskMap.ContainsKey($TaskName)){return $script:taskMap[$TaskName]}
        return $null
    }
    function global:Register-OneTimeTask {
        [CmdletBinding()]
        param([string]$Name,[datetime]$At,[string]$Executable,
              [string]$Arguments,[string]$WorkingDirectory,[string]$Description)
        if($script:taskMap.ContainsKey($Name)){throw 'Duplicate fake OS task.'}
        $script:taskMap[$Name]=[pscustomobject]@{
            TaskName=$Name;State='Ready'
            Triggers=@([pscustomobject]@{StartBoundary=$At.ToString('o')})
            Actions=@([pscustomobject]@{Execute=$Executable;Arguments=$Arguments;WorkingDirectory=$WorkingDirectory})
        }
        return $Name
    }

    $parent='CodexResume-20261104-1420-1234abcd'
    $jobFile=Join-Path $temp ($parent+'.json')
    $job | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jobFile -Encoding utf8
    $runtime=Join-Path $temp 'runtime'
    [void](New-Item -ItemType Directory -Path $runtime -Force)
    [void](New-Item -ItemType File -Path (Join-Path $runtime 'CodexRunJob.vbs') -Force)

    $scheduled=(Get-Date).AddHours(2).AddSeconds(37)
    $child=Register-CodexQuotaContinuation -Job $job -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime -When $scheduled
    Require ($child.Name -match '^CodexResume-' -and $script:taskMap.Count -eq 1) 'One verified child not registered.'
    $payload=SettingsStore\Read-JsonSettings -Path (Join-Path $temp ($child.Name+'.json'))
    Require ($payload.parentJob -ceq $parent -and $payload.retryAttempt -eq 1) 'Child parent linkage or attempt was lost.'
    Require ($payload.sessionId -ceq $job.sessionId -and $payload.accountId -ceq $account) 'Child identity changed.'
    Require ($payload.access -ceq $job.access -and $payload.runtimeFingerprint -ceq $job.runtimeFingerprint) 'Child permission or pinned runtime changed.'
    Require ([string]$payload.message -match 'do not repeat completed changes') 'Child lacks duplicate-side-effect caution.'
    $again=Register-CodexQuotaContinuation -Job $job -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime -When $scheduled.AddMinutes(5)
    Require ($again.Name -ceq $child.Name -and $script:taskMap.Count -eq 1) 'Repeated parent created a second child.'
    # A persisted intent is not proof of the OS action or instruction.
    $action=$script:taskMap[$child.Name].Actions[0]
    $originalArgs=$action.Arguments
    $action.Arguments='//B //Nologo "wrong-runner.vbs" "wrong-job.json"'
    $refused=$false
    try{[void](Register-CodexQuotaContinuation -Job $job -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime -When $scheduled)}catch{$refused=$true}
    Require $refused 'Tampered Windows task action was trusted.'
    $action.Arguments=$originalArgs

    $savedMessage=[string]$payload.message
    $payload.message='Unexpected instruction'
    SettingsStore\Write-JsonSettings -Path (Join-Path $temp ($child.Name+'.json')) -Value $payload
    $refused=$false
    try{[void](Register-CodexQuotaContinuation -Job $job -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime -When $scheduled)}catch{$refused=$true}
    Require $refused 'Tampered child instruction was trusted.'
    $payload.message=$savedMessage
    SettingsStore\Write-JsonSettings -Path (Join-Path $temp ($child.Name+'.json')) -Value $payload
    # Exercise the worker boundary, not just registration: a verified quota
    # deferral must persist the parent outcome and reference exactly that child.
    $quota.recommendedResetAt=[DateTimeOffset]::UtcNow.AddHours(2).ToUnixTimeSeconds()
    Require (Try-DeferCodexQuotaJob -Job $job -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime -Quota $quota -ExitCode 1) 'Worker failed to record verified quota deferral.'
    $deferred=Read-JobOutcome -Path (Join-Path $temp ($parent+'.result.json'))
    Require ($deferred.status -ceq 'deferred' -and $deferred.attempt -eq 0 -and
      $deferred.nextJob -ceq $child.Name -and $deferred.exitCode -eq 1) 'Parent outcome missing deferred status or child link.'
    Require ($script:taskMap.Count -eq 1 -and $script:threadChecks -gt 0) 'Worker failed to verify live conversation before deferral.'
    $script:threadAvailable=$false
    Require (-not (Try-DeferCodexQuotaJob -Job $job -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime -Quota $quota -ExitCode 1)) 'Missing thread still registered a continuation.'
    $script:threadAvailable=$true
    Require ($script:taskMap.Count -eq 1) 'Unverified thread created duplicate child.'
    $quota.model='another-model'
    Require (-not (Try-DeferCodexQuotaJob -Job $job -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime -Quota $quota -ExitCode 1)) 'Worker must not defer mismatched model quota.'
    Require ($script:taskMap.Count -eq 1) 'Mismatched model created a continuation.'
    $quota.model='test-model'


    # A manually removed pending child must not be recreated by an old parent.
    [void]$script:taskMap.Remove($child.Name)
    $refused=$false
    try{[void](Register-CodexQuotaContinuation -Job $job -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime -When $scheduled.AddMinutes(10))}catch{$refused=$true}
    Require ($refused -and $script:taskMap.Count -eq 0) 'Cancelled/absent continuation was recreated.'
    $job.retryAttempt=3
    Require (-not (Test-CodexContinuationPolicy ([pscustomobject]@{retryAttempt=4;continuationPolicy=$job.continuationPolicy}))) 'Attempt four accepted.'
    $refused=$false
    try{[void](Register-CodexQuotaContinuation -Job $job -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime -When $scheduled)}catch{$refused=$true}
    Require ($refused -and $script:taskMap.Count -eq 0) 'Fourth continuation registered.'
    Write-Host 'Quota policy: terminal evidence, matched reset, idempotent child, legacy isolation, cancellation and bounds PASS.' -ForegroundColor Green
}finally{
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
