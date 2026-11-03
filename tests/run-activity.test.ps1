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
$script:ui.Dashboard.activityPanel.Controls.Add($script:ui.Dashboard.activityLabel)
try {
    $form.Show()
    $running=[pscustomobject]@{Name='CodexResume-20261102-1501-f0e770de';Repo='C:\sandbox\example';Status='Running'}
    Update-DashboardActivity -Items @($running) -Directory $temp
    Require (-not $script:ui.Dashboard.activityPanel.Visible) 'Duplicate running ticker must not compete with the Aero working bar.'
    Require (-not $script:ui.Dashboard.ContainsKey('activitySpinner')) 'Obsolete spinner must not coexist with indeterminate Aero.'
    $name=[string]$running.Name
    [void](Write-JobOutcome -Path (Join-Path $temp ($name+'.result.json')) -Status 'completed' -ExitCode 0)
    @('{"type":"item.completed","item":{"type":"agent_message","text":"SCHEDULER_QA_COMPLETED"}}','{"type":"turn.completed"}') |
        Set-Content -LiteralPath (Join-Path $temp ($name+'.jsonl'))
    Update-DashboardActivity -Items @() -Directory $temp
    Require ($script:ui.Dashboard.activityPanel.Visible) 'Latest result must appear after work ends.'
    Require ($script:ui.Dashboard.activityLabel.Text -ceq "Latest: COMPLETED | $name | SCHEDULER_QA_COMPLETED") 'Latest result must be readable with ASCII separators and the exact Codex reply.'
    $next=[pscustomobject]@{Name='CodexResume-20261102-1700-abc12345';Repo='C:\sandbox\example';Status='Scheduled'}
    Update-DashboardActivity -Items @($next) -Directory $temp
    Require ($script:ui.Dashboard.activityPanel.Visible) 'Scheduled-but-not-running task must not suppress latest results.'
    Write-Host 'Activity indicator: genuine Running, completed output, and scheduled idle PASS.'
} finally {
    $form.Dispose()
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-NoUnhandledWinFormsErrors
