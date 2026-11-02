# Activity indication is driven only by authoritative task state and saved outcomes.
# No Windows task creation, external Codex access or simulated percentage complete.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WinFormsEventGuard.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexData.ps1')
. (Join-Path $root 'CodexUiState.ps1')
. (Join-Path $root 'CodexDashboard.ps1')
function Require($ok,[string]$why){if(-not $ok){throw $why}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('codex-activity-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp -Force)
$script:ui=New-CodexUiState
$form=[System.Windows.Forms.Form]::new()
$script:ui.Dashboard.activityPanel=[System.Windows.Forms.Panel]::new()
$form.Controls.Add($script:ui.Dashboard.activityPanel)
$script:ui.Dashboard.activityLabel=[System.Windows.Forms.Label]::new()
$script:ui.Dashboard.activitySpinner=[System.Windows.Forms.Panel]::new()
$script:ui.Dashboard.activityPanel.Controls.Add($script:ui.Dashboard.activityLabel)
$script:ui.Dashboard.activityPanel.Controls.Add($script:ui.Dashboard.activitySpinner)
$script:ui.Dashboard.activityTimer=[System.Windows.Forms.Timer]::new()
$script:ui.Dashboard.activityTimer.Interval=110
try {
    $form.Show()
    $running=[pscustomobject]@{Name='CodexResume-20261102-1501-f0e770de';Repo='C:\sandbox\example';Status='Running'}
    Update-DashboardActivity -Items @($running) -Directory $temp
    Require ($script:ui.Dashboard.activityTimer.Enabled) 'Running task must animate a spinner.'
    Require ($script:ui.Dashboard.activitySpinner.Visible) 'Active spinner must be visible.'
    Require ($script:ui.Dashboard.activityLabel.Text -match 'Codex running') 'Running label missing.'
    Require ($script:ui.Dashboard.activityLabel.Text -notmatch '%|percent') 'Do not fabricate execution progress.'
    $name=[string]$running.Name
    [void](Write-JobOutcome -Path (Join-Path $temp ($name+'.result.json')) -Status 'completed' -ExitCode 0)
    @('{"type":"item.completed","item":{"type":"agent_message","text":"SCHEDULER_QA_COMPLETED"}}','{"type":"turn.completed"}') |
        Set-Content -LiteralPath (Join-Path $temp ($name+'.jsonl'))
    Update-DashboardActivity -Items @() -Directory $temp
    Require (-not $script:ui.Dashboard.activityTimer.Enabled) 'Spinner must stop when no job is running.'
    Require (-not $script:ui.Dashboard.activitySpinner.Visible) 'Spinner must disappear after completion.'
    Require ($script:ui.Dashboard.activityLabel.Text -match 'COMPLETED' -and $script:ui.Dashboard.activityLabel.Text -match 'SCHEDULER_QA_COMPLETED') 'Latest completed result must be visible.'
    $next=[pscustomobject]@{Name='CodexResume-20261102-1700-abc12345';Repo='C:\sandbox\example';Status='Scheduled'}
    Update-DashboardActivity -Items @($next) -Directory $temp
    Require (-not $script:ui.Dashboard.activitySpinner.Visible) 'Scheduled-but-not-running task must not show active spinner.'
    Write-Host 'Activity indicator: genuine Running, completed output, and scheduled idle PASS.'
} finally {
    $script:ui.Dashboard.activityTimer.Dispose()
    $form.Dispose()
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-NoUnhandledWinFormsErrors
