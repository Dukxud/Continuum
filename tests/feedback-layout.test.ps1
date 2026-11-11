# The interface must display actionable warnings without a permanent
# status ticker, latest-result strip, or usage disclaimer.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WinFormsEventGuard.ps1')
Add-Type -AssemblyName System.Windows.Forms
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'components/WindowShell/WindowShell.psm1') -Force -ErrorAction Stop
. (Join-Path $root 'legacy/winforms/CodexUiState.ps1')
function Require($ok,[string]$message){if(-not $ok){throw $message}}
$forms=Get-Content -LiteralPath (Join-Path $root 'legacy/winforms/CodexUiForms.ps1') -Raw
$dashboard=Get-Content -LiteralPath (Join-Path $root 'legacy/winforms/CodexDashboard.ps1') -Raw
$usage=Get-Content -LiteralPath (Join-Path $root 'legacy/winforms/CodexUiUsage.ps1') -Raw
Require ($forms -notmatch 'usageNotice|autoResumeCheck|Ready\. Keep Windows awake') 'Obsolete status/disclaimer controls remain.'
Require ($dashboard -notmatch 'activityPanel|activityLabel|Update-DashboardActivity') 'Latest result ticker remains in dashboard.'
Require ($usage -match 'Set-UsageUnavailable' -and $usage -notmatch 'usageNotice|card\.Updated') 'Usage failures must appear inside cards without an updated-time footer.'
Require ($forms -notmatch 'refreshSessions|refreshUsage|refreshRuns|Updated =') 'Redundant refresh buttons or timestamps remain.'
$tokens=$null;$parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseInput($forms,[ref]$tokens,[ref]$parseErrors)
if($parseErrors){throw ($parseErrors | Out-String)}
foreach($fn in @('Update-Status','Clear-SchedulerAlert')){
    $definition=@($ast.FindAll({param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fn
    },$true))
    Require ($definition.Count -eq 1) "Expected one $fn implementation."
    Invoke-Expression $definition[0].Extent.Text
}
$script:ui=New-CodexUiState
$form=[System.Windows.Forms.Form]::new()
$status=Add-DesktopLabel -Parent $form -Text '' -X 8 -Y 8 -Width 300
$status.Visible=$false
Require ($status.Text -ceq '') 'Actual warning label creation rejected empty text.'
try {
    $form.Show()
    Update-Status 'Conversations updated'
    Require (-not $status.Visible) 'Routine updates must not display a footer.'
    Update-Status 'Quota request failed' -Alert
    Require ($status.Visible -and $status.Text -eq 'Quota request failed') 'Actionable error was hidden.'
    Clear-SchedulerAlert
    Require (-not $status.Visible -and [string]::IsNullOrWhiteSpace($script:ui.Preferences.alertMessage)) 'Dismissing an error must restore the clean layout.'
    Write-Host 'No redundant refresh controls, timestamps or tickers; warning-only feedback PASS.'
} finally {$form.Dispose()}
Assert-NoUnhandledWinFormsErrors
