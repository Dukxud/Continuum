# Local time helpers: a near-term default must not drift after manual edits.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexScheduleTime.ps1')
function Require($ok,[string]$message){if(-not $ok){throw $message}}
$now=[datetime]'2026-11-02T17:50:15'
$default=Get-CodexSuggestedRunTime -Now $now
Require ($default -eq [datetime]'2026-11-02T17:53:00') 'Default should be 2 minutes ahead, rounded to the next full minute.'
Require ((Get-CodexSuggestedRunTime -Now ([datetime]'2026-11-02T17:50:00')) -eq [datetime]'2026-11-02T17:52:00') 'An exact minute must not gain an extra minute.'
Require ((Get-CodexSuggestedRunTime -Now ([datetime]'2026-12-31T23:59:30')) -eq [datetime]'2027-01-01T00:02:00') 'Default must cross year boundary correctly.'
Require ((Step-CodexScheduledRunTime -Time $default -Direction 1 -Now $now) -eq $default.AddMinutes(1)) 'Plus must add one minute.'
Require ((Step-CodexScheduledRunTime -Time $default -Direction -1 -Now $now) -eq $default.AddMinutes(-1)) 'Minus must subtract one minute.'
$near=[datetime]'2026-11-02T17:51:00'
Require ((Step-CodexScheduledRunTime -Time $near -Direction -1 -Now $now) -eq $near) 'Minus must not schedule inside the 30-second safety window.'
$actions=Get-Content -LiteralPath (Join-Path $root 'CodexUiActions.ps1') -Raw
$forms=Get-Content -LiteralPath (Join-Path $root 'CodexUiForms.ps1') -Raw
$lifecycle=Get-Content -LiteralPath (Join-Path $root 'CodexUiLifecycle.ps1') -Raw
foreach($fragment in @('scheduleTimeEdited','scheduleTimeUpdating','Refresh-SuggestedRunTime','minusTime.Add_Click','plusTime.Add_Click')){
    Require ($actions.Contains($fragment)) "Time control wiring missing: $fragment"
}
Require (-not $actions.Contains('countdownTimer.Add_Tick({ Refresh-SuggestedRunTime })')) 'Do not subscribe to dashboard timer before dashboard initialization.'
Require ($lifecycle.IndexOf('Initialize-Dashboard') -ge 0 -and $lifecycle.IndexOf('countdownTimer.Add_Tick({ Refresh-SuggestedRunTime })') -gt $lifecycle.IndexOf('Initialize-Dashboard')) 'Scheduling timer handler must be wired after dashboard initialization.'
Require ($forms.Contains('if ($restoredTime)') -and $forms.Contains('scheduleTimeEdited=$true')) 'Future user-selected times must not be overwritten.'
Write-Host 'Two-minute default, rollover, one-minute step, guard, and manual-edit protection PASS.'
