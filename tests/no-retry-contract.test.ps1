# No retry module, job payload, or background registration is allowed
# in the single-execution contract. Actual worker behavior is covered by
# codex-worker-integration.test.ps1 using an isolated fake Codex CLI.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexRunEngine.ps1')
function Require($condition,[string]$message){if(-not $condition){throw $message}}
$worker=Get-Content -LiteralPath (Join-Path $root 'CodexRunEngine.ps1') -Raw
$ui=Get-Content -LiteralPath (Join-Path $root 'CodexUiActions.ps1') -Raw
$package=Get-Content -LiteralPath (Join-Path $root 'scripts/Package-CodexScheduler.ps1') -Raw
Require (-not (Test-Path -LiteralPath (Join-Path $root 'CodexRetry.js'))) 'Unused retry helper still exists.'
Require ($worker -notmatch 'Schedule-LimitRetry|CodexRetry|retryAttempt|autoResume') 'Worker still contains automatic retry machinery.'
Require ($ui -notmatch 'autoResumeCheck|autoResume\s*=|retryAttempt\s*=') 'UI still schedules retry-capable payloads.'
$runtimeFiles=Get-CodexRuntimeFiles
Require ($runtimeFiles -cnotcontains 'CodexRetry.js') 'Pinned worker bundle includes the retry helper.'
Require ($runtimeFiles -ccontains 'CodexUsage.js') 'Pinned worker lost its usage and identity reader.'
Require ($package -notmatch 'CodexRetry\.js') 'Release includes the retry helper.'
Require ($package -match 'CodexScheduleTime\.ps1') 'Release omitted the scheduling time helper.'
Require ($worker -match "Status 'blocked'" -and $worker -match "Status 'failed'") 'Blocked/failed outcomes were removed.'
Write-Host 'One schedule/one execution: no retry registration, preserved safety, clean runtime manifest PASS.'
