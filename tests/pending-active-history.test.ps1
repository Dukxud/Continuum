# Upcoming runs and recent history are distinct views.
# Exercises the UI projection without creating, modifying or launching Windows tasks.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WinFormsEventGuard.ps1')
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'legacy/winforms/CodexUiState.ps1')
$appDir=Join-Path ([IO.Path]::GetTempPath()) ('codex-upcoming-only-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $appDir -Force)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/backend/CodexJobStore.ps1')
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
function Update-DashboardActivity { param([object[]]$Items,[string]$Directory) }
function Request-UsageRefresh {}
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'legacy/winforms/CodexUiPending.ps1')
function Require($condition,[string]$message){if(-not $condition){throw $message}}
$now=Get-Date
$failed=[pscustomobject]@{Name='BP090-Codex-Test';When=$now.AddHours(-2);Repo='-';Description='Historical failure';Session='-';Model='';Status='Failed (task exit 1)'}
$ended=[pscustomobject]@{Name='BP091-Codex-Test';When=$now.AddHours(-1);Repo='-';Description='Historical completion';Session='-';Model='';Status='Ended (no result recorded)'}
$scheduled=[pscustomobject]@{Name='CodexResume-20261102-1700-abc12345';When=$now.AddMinutes(30);Repo='C:\qa';Description='QA continuation';Session='00000000-0000-0000-0000-000000000001';Model='test-model';Status='Scheduled'}
$running=[pscustomobject]@{Name='CodexResume-20261102-1600-abc12346';When=$now.AddMinutes(-1);Repo='C:\qa';Description='Running';Session='00000000-0000-0000-0000-000000000001';Model='test-model';Status='Running'}
$completedName='CodexResume-20261102-1501-f0e770de'
[void](Write-JobOutcome -Path (Join-Path $appDir ($completedName+'.result.json')) -Status 'completed' -ExitCode 0)
try {
    Apply-PendingList -Items @($failed,$scheduled,$running,$ended)
    Require ($grid.Rows.Count -eq 2) 'Main queue must contain only scheduled and running jobs.'
    Require ($pending.Text -eq 'Upcoming runs (2)') 'Main queue heading must say Upcoming runs.'
    Require ($script:ui.Dashboard.pendingSnapshot.Count -eq 2) 'Layout count must exclude historical jobs.'
    Require ($script:ui.Dashboard.pendingSnapshot.Count -eq 2) 'Upcoming snapshot contained history.'
    Require ($script:ui.Dashboard.historySnapshot.Count -eq 2) 'Historical Windows tasks disappeared from Recent runs.'
    Require (@($grid.Rows | Where-Object { $_.Tag -eq $completedName -or $_.Tag -eq $failed.Name }).Count -eq 0) 'Historical row leaked into Upcoming runs.'
    $scheduledRow=@($grid.Rows | Where-Object { $_.Tag -eq $scheduled.Name })[0]
    $grid.CurrentCell=$scheduledRow.Cells[0]
    $scheduledRow.Selected=$true
    Apply-PendingList -Items @($failed,$scheduled,$running,$ended)
    $unchanged=@($grid.Rows | Where-Object { $_.Tag -eq $scheduled.Name })[0]
    Require ([object]::ReferenceEquals($scheduledRow,$unchanged) -and $unchanged.Selected) 'Refreshing the queue caused row flicker or lost selection.'
    Require ($cancelRun.Enabled) 'Scheduled task did not enable cancellation.'
    # Once both jobs finish, no historical record (including a saved outcome)
    # can make the Upcoming runs section reappear.
    Apply-PendingList -Items @($failed,$ended)
    Require ($grid.Rows.Count -eq 0 -and $script:ui.Dashboard.pendingSnapshot.Count -eq 0) 'Previous runs kept the main queue visible.'
    Require ($pending.Text -eq 'Upcoming runs (0)') 'Empty queue heading is misleading.'
    Require (@(Get-CodexRunHistory -Directory $appDir).Count -eq 1) 'Saved completed outcome missing from history.'
    Hide-CodexRunRecord -Directory $appDir -Name $completedName
    Hide-CodexRunRecord -Directory $appDir -Name $failed.Name
    Apply-PendingList -Items @($failed,$ended)
    Require ($grid.Rows.Count -eq 0) 'Hidden results appeared in Upcoming runs.'
    Require ($script:ui.Dashboard.historySnapshot.Count -eq 1) 'Hidden Windows task reappeared in Recent runs.'
    Require (@(Get-CodexRunHistory -Directory $appDir).Count -eq 0) 'Hidden saved result reappeared in history.'
    Require (Test-Path -LiteralPath (Join-Path $appDir ($completedName+'.result.json'))) 'Hiding history deleted the result file.'
    # A previously hidden ID must still be displayed if Task Scheduler says
    # it is now running (safety: hiding is never an execution control).
    Hide-CodexRunRecord -Directory $appDir -Name $scheduled.Name
    Apply-PendingList -Items @($scheduled,$ended)
    Require ($grid.Rows.Count -eq 1 -and [string]$grid.Rows[0].Tag -ceq $scheduled.Name) 'Hiding a record suppressed an active Windows task.'
    Write-Host 'Upcoming-only queue, live status, stable refresh, empty layout, and separate history PASS.'
} finally {
    $grid.Dispose()
    $cancelRun.Dispose()
    $pending.Dispose()
    $emptyRuns.Dispose()
    $script:ui.Dashboard.compactToggle.Dispose()
    Remove-Item -LiteralPath $appDir -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-NoUnhandledWinFormsErrors
