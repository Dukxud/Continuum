# Regression: old Windows task outcomes must not occupy the live queue.
# No scheduled task is registered, started, or removed by this test.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WinFormsEventGuard.ps1')
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexUiState.ps1')
$script:ui=New-CodexUiState
$script:ui.Dashboard.compactToggle=[System.Windows.Forms.CheckBox]::new()
$grid=[System.Windows.Forms.DataGridView]::new()
$grid.AllowUserToAddRows=$false
foreach($name in @('Scheduled','Countdown','Project','Details','Session')){[void]$grid.Columns.Add($name,$name)}
$cancelRun=[System.Windows.Forms.Button]::new()
$pending=[System.Windows.Forms.Label]::new()
$emptyRuns=[System.Windows.Forms.Label]::new()
function Update-DashboardLayout {}
function Update-DashboardCountdowns {}
function Request-UsageRefresh {}
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexUiPending.ps1')
function Require($check,[string]$message){if(-not $check){throw $message}}
$now=Get-Date
$failed=[pscustomobject]@{Name='BP090-Codex-Test';When=$now.AddHours(-2);Repo='-';Description='Old Windows task';Session='-';Model='';Status='Failed (task exit 1)'}
$ended=[pscustomobject]@{Name='BP091-Codex-Test';When=$now.AddHours(-1);Repo='-';Description='Old Windows task';Session='-';Model='';Status='Ended (no result recorded)'}
$upcoming=[pscustomobject]@{Name='CodexResume-test';When=$now.AddMinutes(30);Repo='C:\qa';Description='QA continuation';Session='00000000-0000-0000-0000-000000000001';Model='test-model';Status='Scheduled'}
try {
    Apply-PendingList -Items @($failed,$upcoming,$ended)
    Require ($script:ui.Dashboard.pendingSnapshot.Count -eq 1) 'Live queue included old results.'
    Require ($script:ui.Dashboard.pendingSnapshot[0].Name -eq $upcoming.Name) 'Next run is not the actual upcoming task.'
    Require ($script:ui.Dashboard.historySnapshot.Count -eq 2) 'History omitted a Windows-only task.'
    Require ($grid.Rows.Count -eq 1) 'Full mode showed completed/failed Windows tasks.'
    Require ($pending.Text -eq 'Upcoming runs (1)') 'Active-run heading is incorrect.'
    Apply-PendingList -Items @($failed,$ended)
    Require ($script:ui.Dashboard.pendingSnapshot.Count -eq 0) 'No upcoming task must mean no next-run card.'
    Require ($grid.Rows.Count -eq 0) 'Old results must not create a live queue row.'
    Require ($script:ui.Dashboard.historySnapshot.Count -eq 2) 'History was lost after active work cleared.'
    Write-Host 'Active dashboard and Windows-only history are correctly separated.'
} finally {
    $grid.Dispose()
    $cancelRun.Dispose()
    $pending.Dispose()
    $emptyRuns.Dispose()
    $script:ui.Dashboard.compactToggle.Dispose()
}
Assert-NoUnhandledWinFormsErrors
