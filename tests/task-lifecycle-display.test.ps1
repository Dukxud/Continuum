# Local-only UI projection test: Windows Task Scheduler APIs are simulated,
# no Codex execution and no real task creation, removal, or modification.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/backend/CodexData.ps1')
function Require($ok,[string]$message){if(-not $ok){throw $message}}

$now=Get-Date
$past=$now.AddMinutes(-20)
$runningInfo=[pscustomobject]@{LastRunTime=$past;LastTaskResult=0}
Require ((Get-CodexTaskDisplayState -When $past -TaskState 'Running' -Now $now) -eq 'Running') 'Running task cannot display Due now.'
Require ((Get-CodexTaskDisplayState -When $past -TaskState 'Ready' -TaskInfo $runningInfo -Now $now) -eq 'Ended (no result recorded)') 'Task Scheduler exit zero is NOT verified Codex completion.'
Require ((Get-CodexTaskDisplayState -When $past -TaskState 'Ready' -TaskInfo ([pscustomobject]@{LastRunTime=$past;LastTaskResult=1}) -Now $now) -eq 'Failed (task exit 1)') 'Nonzero task exit must be visible.'
Require ((Get-CodexTaskDisplayState -When $past -TaskState 'Ready' -TaskInfo ([pscustomobject]@{LastRunTime=[datetime]'1999-11-30';LastTaskResult=0}) -Now $now) -eq 'Overdue (execution unconfirmed)') 'Never claim execution on an unstarted task.'
Require ((Get-CodexTaskDisplayState -When $past -TaskState 'Ready' -Outcome ([pscustomobject]@{status='blocked'}) -Now $now) -eq 'Blocked') 'Persisted blocked outcome must be visible.'
Require ((Get-CodexTaskDisplayState -When $past -TaskState 'Ready' -Outcome ([pscustomobject]@{status='finished'}) -Now $now) -eq 'Finished') 'An interactive terminal exit must not be presented as verified Codex completion.'
Require ((Get-CodexTaskDisplayState -When $now.AddMinutes(8) -TaskState 'Ready' -Now $now) -eq 'Scheduled') 'Future task should remain scheduled.'

$temp=Join-Path ([IO.Path]::GetTempPath()) ('codex-display-status-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp -Force)
try {
    function New-FakeTask([string]$name,[datetime]$when,[string]$state) {
        return [pscustomobject]@{
            TaskName=$name;TaskPath='\';State=$state
            Actions=@([pscustomobject]@{WorkingDirectory=$temp;Arguments=''})
            Triggers=@([pscustomobject]@{StartBoundary=$when.ToString('yyyy-MM-ddTHH:mm:ss')})
        }
    }
    $runName='CodexResume-running-00000001'
    $nextName='CodexResume-upcoming-00000002'
    $doneName='CodexResume-finished-00000003'
    $oldName='CodexResume-obsolete-00000004'
    $script:fakeTasks=@(
        (New-FakeTask $nextName ($now.AddMinutes(30)) 'Ready'),
        (New-FakeTask $runName ($now.AddMinutes(-20)) 'Running'),
        (New-FakeTask $oldName ($now.AddDays(-4)) 'Ready'),
        (New-FakeTask $doneName ($now.AddMinutes(-40)) 'Ready')
    )
    foreach($name in @($runName,$nextName,$doneName)) {
        [pscustomobject]@{
            sessionId='00000000-0000-0000-0000-000000000001'
            repo=$temp;model='test-model';effort='high';access='read-only'
            message='Test task';createdAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $temp ($name+'.json'))
    }
    # A scheduled child is still safely cancellable but visibly identified
    # as waiting for an authoritative quota reset.
    $nextPayload=Get-Content -LiteralPath (Join-Path $temp ($nextName+'.json')) -Raw | ConvertFrom-Json
    $nextPayload | Add-Member -NotePropertyName continuationPolicy -NotePropertyValue ([pscustomobject]@{schema=1;mode='quota-only';maxContinuations=3})
    $nextPayload | Add-Member -NotePropertyName retryAttempt -NotePropertyValue 1
    $nextPayload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $temp ($nextName+'.json'))
    $script:lastTaskInfo=@{
        $doneName=[pscustomobject]@{LastRunTime=$now.AddMinutes(-40);LastTaskResult=0}
    }
    function Get-ScheduledTask {
        param([string]$TaskName)
        if($TaskName -eq 'CodexResume-*') {return $script:fakeTasks}
        return @()
    }
    function Get-ScheduledTaskInfo {
        param([string]$TaskName,[string]$TaskPath)
        if($script:lastTaskInfo.ContainsKey($TaskName)){return $script:lastTaskInfo[$TaskName]}
        throw "No mock outcome for $TaskName"
    }
    $records=@(Get-UpcomingCodexTasks -AppDirectory $temp)
    Require ($records.Count -eq 3) 'Only running, scheduled, and recent tasks should appear.'
    Require ($records[0].Name -eq $runName -and $records[0].Status -eq 'Running') 'Running work must appear before scheduled and historical work.'
    Require ($records[1].Name -eq $nextName -and $records[1].Status -eq 'Scheduled') 'Upcoming tasks must follow active work.'
    Require ($records[1].QuotaContinuation -eq $true -and $records[0].QuotaContinuation -eq $false) 'Only a pending quota child may be labeled waiting for quota.'
    Require ($records[2].Name -eq $doneName -and $records[2].Status -eq 'Ended (no result recorded)') 'Recent work without a worker outcome must be honestly labeled.'
    Write-JobOutcome -Path (Join-Path $temp ($doneName+'.result.json')) -Status 'completed' -ExitCode 0 | Out-Null
    $after=@(Get-UpcomingCodexTasks -AppDirectory $temp)
    Require ($after[2].Status -eq 'Completed') 'Persisted Codex completion should supersede unverified Task Scheduler exit.'
    Write-Host 'Task lifecycle display: running, future, stale, unverified, failure, and recorded result PASS.'
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
