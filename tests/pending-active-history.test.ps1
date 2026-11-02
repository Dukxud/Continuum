# Regression: old Windows task outcomes must not occupy the live queue.
# No scheduled task is registered, started, or removed by this test.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WinFormsEventGuard.ps1')
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexUiState.ps1')
$appDir=Join-Path ([IO.Path]::GetTempPath()) ('codex-persistent-runs-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $appDir -Force)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexJobStore.ps1')
$script:ui=New-CodexUiState
$script:ui.Dashboard.compactToggle=[System.Windows.Forms.CheckBox]::new()
$grid=[System.Windows.Forms.DataGridView]::new()
$grid.AllowUserToAddRows=$false
foreach($name in @('Scheduled','Countdown','Project','Details','Session')){[void]$grid.Columns.Add($name,$name)}
$cancelRun=[System.Windows.Forms.Button]::new()
$viewResult=[System.Windows.Forms.Button]::new()
$pending=[System.Windows.Forms.Label]::new()
$emptyRuns=[System.Windows.Forms.Label]::new()
function Update-DashboardLayout {}
function Update-DashboardCountdowns {}
function Update-DashboardActivity { param([object[]]$Items,[string]$Directory) }
function Request-UsageRefresh {}
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexUiPending.ps1')
function Require($check,[string]$message){if(-not $check){throw $message}}
$now=Get-Date
$failed=[pscustomobject]@{Name='BP090-Codex-Test';When=$now.AddHours(-2);Repo='-';Description='Old Windows task';Session='-';Model='';Status='Failed (task exit 1)'}
$ended=[pscustomobject]@{Name='BP091-Codex-Test';When=$now.AddHours(-1);Repo='-';Description='Old Windows task';Session='-';Model='';Status='Ended (no result recorded)'}
$upcoming=[pscustomobject]@{Name='CodexResume-test';When=$now.AddMinutes(30);Repo='C:\qa';Description='QA continuation';Session='00000000-0000-0000-0000-000000000001';Model='test-model';Status='Scheduled'}
$completedName='CodexResume-20261102-1501-f0e770de'
[void](Write-JobOutcome -Path (Join-Path $appDir ($completedName+'.result.json')) -Status 'completed' -ExitCode 0)
[pscustomobject]@{repo='C:\qa';sessionId='00000000-0000-0000-0000-000000000001';message='SCHEDULER_QA_COMPLETED'} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appDir ($completedName+'.json'))
try {
    Apply-PendingList -Items @($failed,$upcoming,$ended)
    Require ($script:ui.Dashboard.pendingSnapshot.Count -eq 1) 'Live queue included old results.'
    Require ($script:ui.Dashboard.pendingSnapshot[0].Name -eq $upcoming.Name) 'Next run is not the actual upcoming task.'
    Require ($script:ui.Dashboard.historySnapshot.Count -eq 3) 'Persisted outcome was missing from history.'
    Require ($grid.Rows.Count -eq 4) 'Main Runs table must retain three finished results with the active task.'
    Require ($pending.Text -eq 'Runs (1 active, 3 recent)') 'Active/recent heading is incorrect.'
    $completed=@($grid.Rows | Where-Object { [string]$_.Tag -ceq $completedName }) | Select-Object -First 1
    Require ($completed -and $completed.Cells[1].Value -eq 'completed') 'Saved completion was not visible/selectable.'
    Require ($completed.Cells[1].Tag -eq 'history') 'A finished job must not show a countdown bar.'
    $grid.CurrentCell=$completed.Cells[0]
    $completed.Selected=$true
    $before=$completed
    Apply-PendingList -Items @($failed,$upcoming,$ended)
    $after=@($grid.Rows | Where-Object { [string]$_.Tag -ceq $completedName }) | Select-Object -First 1
    Require ([object]::ReferenceEquals($before,$after)) 'Periodic refresh rebuilt identical rows, causing a flicker.'
    Require ($after.Selected -and $viewResult.Enabled) 'Periodic refresh discarded a selected finished run.'
    Apply-PendingList -Items @($failed,$ended)
    Require ($script:ui.Dashboard.pendingSnapshot.Count -eq 0) 'Finished jobs must not enter the active queue.'
    Require ($grid.Rows.Count -eq 3) 'Previous runs disappeared when the next run completed.'
    Require (@($grid.Rows | Where-Object { [string]$_.Tag -ceq $completedName }).Count -eq 1) 'Persisted result was lost after removing the active row.'
    Require ($viewResult.Enabled) 'Selected finished result lost its View action after reshuffling.'
    Write-Host 'Recent results persist, remain selectable, survive refresh, and keep countdowns separate.'
} finally {
    $grid.Dispose()
    $cancelRun.Dispose()
    $viewResult.Dispose()
    $pending.Dispose()
    $emptyRuns.Dispose()
    $script:ui.Dashboard.compactToggle.Dispose()
    Remove-Item -LiteralPath $appDir -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-NoUnhandledWinFormsErrors
