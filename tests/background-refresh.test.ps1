# Verify costly data reads are dispatched to background jobs, never from refresh handlers.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexUiState.ps1')
$script:ui = New-CodexUiState
$gui = @('CodexUiRefresh.ps1','CodexUiSelection.ps1','CodexUiPending.ps1','CodexUiUsage.ps1') | ForEach-Object { Get-Content -LiteralPath (Join-Path $root $_) -Raw } | Out-String
$data = Get-Content -LiteralPath (Join-Path $root 'CodexData.ps1') -Raw
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($gui, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors | Out-String) }
if ($gui -match 'Get-CodexSessionCollision|Get-CimInstance\s+Win32_Process') { throw 'Unreliable Codex process detection must be removed from UI and runner.' }
if ($data -match 'Get-CimInstance\s+Win32_Process') { throw 'Process inspection remains in background code.' }
if ($gui -notmatch 'Get-ReportedThreadDirectory' -or $gui -notmatch 'Find-SessionRepository \$SelectedSession \$reportedCwd') { throw 'The background selection job must prefer thread/read metadata.' }
if ($data -notmatch 'thread/read' -or $data -notmatch 'Get-ReportedThreadDirectory') { throw 'Codex metadata lookup missing from the data helper.' }
if ($gui -notmatch 'Start-ThreadJob' -or $gui -notmatch '\$dataPoll\.Add_Tick') { throw 'Background refresh and result polling missing.' }
if ($data -notmatch "Get-ScheduledTask -TaskName 'CodexResume-\*'") { throw 'Pending refresh must use task name filtering.' }
$worker = Get-Content -LiteralPath (Join-Path $root 'CodexRunEngine.ps1') -Raw
if ($worker -notmatch 'Get-CodexRuntimeFiles' -or $worker -notmatch 'Assert-RuntimeFingerprint') { throw 'Scheduled runner must use an immutable runtime snapshot.' }
$definitions = @($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Refresh-SessionList','Refresh-PendingList','Request-SelectionLookup','Start-DataRead','Request-SystemRefresh')}, $true))
if ($definitions.Count -ne 5) { throw 'Expected five async data-refresh entrypoints.' }
foreach ($definition in $definitions | Where-Object Name -in @('Refresh-SessionList','Refresh-PendingList','Request-SelectionLookup')) {
    if ($definition.Extent.Text -match 'Get-ScheduledTask|Get-Content|Get-RecentCliSessions|Find-SessionRepository|Read-SessionModel') { throw "UI entrypoint $($definition.Name) performs blocking work." }
}
# Start-DataRead must coalesce an in-flight request, not start parallel duplicates.
Invoke-Expression (@($definitions | Where-Object Name -eq 'Start-DataRead')[0].Extent.Text)
$script:ui.Async.dataJobs = @{}; $script:ui.Async.dataQueued = @{}; $script:startedJobs = 0
function Start-ThreadJob { param($ArgumentList,$ScriptBlock) $script:startedJobs++; [pscustomobject]@{ State = 'Running' } }
function Update-Status { param($Text) throw "Unexpected start failure: $Text" }
$appDir = 'C:\fake'
Start-DataRead -Kind 'pending'
Start-DataRead -Kind 'pending'
if ($script:startedJobs -ne 1 -or -not $script:ui.Async.dataQueued['pending']) { throw 'Duplicate pending refresh was not coalesced.' }

# Exercise the real coordinator, keeping underlying readers mocked. Full
# refresh updates all sources; fast status checks and model changes are scoped.
Invoke-Expression (@($definitions | Where-Object Name -eq 'Request-SystemRefresh')[0].Extent.Text)
$script:sessionCalls=0;$script:pendingCalls=0;$script:usageCalls=0
function Refresh-SessionList { $script:sessionCalls++ }
function Refresh-PendingList { $script:pendingCalls++ }
function Request-UsageRefresh { $script:usageCalls++ }
Request-SystemRefresh
if($script:sessionCalls -ne 1 -or $script:pendingCalls -ne 1 -or $script:usageCalls -ne 1 -or
   $script:ui.Async.lastFullRefresh -eq [datetime]::MinValue){throw 'Full system refresh did not update every source.'}
Request-SystemRefresh -Scope TaskStatus
if($script:pendingCalls -ne 2 -or $script:sessionCalls -ne 1 -or $script:usageCalls -ne 1){throw 'Two-second task status check restarted unrelated readers.'}
Request-SystemRefresh -Scope ModelChanged
if($script:usageCalls -ne 2 -or $script:sessionCalls -ne 1 -or $script:pendingCalls -ne 2){throw 'Model change refreshed unrelated sources.'}
$lifecycle=Get-Content -LiteralPath (Join-Path $root 'CodexUiLifecycle.ps1') -Raw
if($lifecycle -notmatch '\$systemRefreshTimer\.Interval = 2000' -or
   $lifecycle -notmatch 'Request-SystemRefresh -Scope \$scope' -or
   $lifecycle -notmatch '\$form\.Add_Activated' -or
   $lifecycle -match '\$runStatusRefresh|\$autoRefresh'){throw 'Refresh lifecycle uses duplicate timers or lacks resume handling.'}
Write-Host 'Single refresh coordinator, async deduplication, 2s task status, 60s full refresh and resume wiring PASS.'
