# Regression: browser renderer termination must leave a functional WPF bar.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WinFormsEventGuard.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexFlowingBar.ps1')
. (Join-Path $root 'CodexAeroBar.ps1')
. (Join-Path $root 'CodexDashboard.ps1')
. (Join-Path $root 'CodexUiState.ps1')
$script:ui = New-CodexUiState
function Require($condition,[string]$message){if(-not $condition){throw $message}}
Require (Test-AeroRenderer) "Aero prerequisite absent: $script:aeroError"
$form=[Windows.Forms.Form]::new()
$form.ClientSize=[Drawing.Size]::new(450,310)
try{
    $bar=New-AeroProgressBar $form 16 22 400 17 'quota'
    Require ($bar.GetType().Name -eq 'WebView2') 'Initial Aero bar not WebView2.'
    Set-AeroProgress $bar 62
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    $bar.Tag.Failure='Simulated WebView2 renderer process exit'
    Ensure-AeroFallback $bar
    $fallbackHost=Get-AeroProgressSurface $bar
    Require ($fallbackHost -is [Windows.Forms.Integration.ElementHost]) 'WPF recovery bar was not created.'
    Require (-not $bar.Visible -and $fallbackHost.Visible) 'Failed WebView must be hidden and WPF visible.'
    Require ([math]::Abs([double](Get-FlowingProgressViewValue $fallbackHost)-62) -lt .001) 'Recovery lost last authoritative percentage.'
    Set-AeroProgress $bar 91
    Require ([math]::Abs([double](Get-FlowingProgressViewValue $fallbackHost)-91) -lt .001) 'Further percentage updates failed after recovery.'
    Set-AeroProgress $bar $null
    Require ($null -eq (Get-FlowingProgressViewValue $fallbackHost)) 'Unknown percentage must remain unknown after recovery.'
    Set-AeroWorking $bar
    Require ($bar.Tag.Working -and $null -eq $bar.Tag.Percent) 'Fallback must not claim an execution percentage.'
    Require ($fallbackHost.AccessibleName -eq 'Codex working; completion unknown') 'Working state lacks an accessible indeterminate label.'
    Require ($fallbackHost.Child.Value -eq 100 -and $fallbackHost.Child.IsIndeterminate) 'Working WPF tube must explicitly report indeterminate state, never measured completion.'
    Set-AeroProgress $bar $null
    Require (-not $bar.Tag.Working -and -not $fallbackHost.Child.IsIndeterminate -and $null -eq (Get-FlowingProgressViewValue $fallbackHost)) 'Fallback did not leave working mode safely.'
    Ensure-AeroFallback $bar
    Require ([object]::ReferenceEquals($fallbackHost,(Get-AeroProgressSurface $bar))) 'Recovery created duplicate controls.'
    Update-AeroAppearance ([ordered]@{quota='violet';time='amber';finish=0;lighting=0;shimmer=100;speed=100;aero=$true})
    $updatedFallback=Get-AeroProgressSurface $bar
    Require ($updatedFallback -ne $fallbackHost -and $fallbackHost.IsDisposed) 'Appearance update did not recreate recovered bar.'
    Require ((Get-FlowingProgressViewValue $updatedFallback) -eq $null) 'Appearance change must retain unknown percentage.'
    # Recovered bars must follow the real DataGridView layout and be destroyed
    # with their row; otherwise they remain stuck on screen after scrolling.
    $grid=[Windows.Forms.DataGridView]::new()
    $grid.Location=[Drawing.Point]::new(15,120)
    $grid.Size=[Drawing.Size]::new(400,160)
    $grid.AllowUserToAddRows=$false
    $grid.RowTemplate.Height=54
    [void]$grid.Columns.Add('When','When')
    [void]$grid.Columns.Add('Countdown','Time')
    $form.Controls.Add($grid)
    [void]$grid.Rows.Add('Next','10m')
    $script:ui.Dashboard.runBarHosts=[Collections.Generic.List[Windows.Forms.Control]]::new()
    $runBar=New-AeroProgressBar $grid 0 0 100 15 'time'
    $script:ui.Dashboard.runBarHosts.Add($runBar)
    $grid.Rows[0].Cells[1].Tag=45
    $runBar.Tag.Failure='Simulated failure in a grid cell'
    Ensure-AeroFallback $runBar
    Sync-DashboardRunBars
    $active=Get-AeroProgressSurface $runBar
    $cell=$grid.GetCellDisplayRectangle(1,0,$true)
    $labelWidth=[math]::Min(93,[math]::Max(59,[int]($cell.Width*.42)))
    Require ($active.Left -eq ($cell.X+$labelWidth+12) -and $active.Width -eq ([math]::Max(20,$cell.Right-$active.Left-9))) 'Recovered bar did not occupy the right side of a single-line grid cell.'
    $grid.Columns[1].Width+=27
    Sync-DashboardRunBars
    $cell=$grid.GetCellDisplayRectangle(1,0,$true)
    $labelWidth=[math]::Min(93,[math]::Max(59,[int]($cell.Width*.42)))
    Require ($active.Left -eq ($cell.X+$labelWidth+12) -and $active.Width -eq ([math]::Max(20,$cell.Right-$active.Left-9))) 'Recovered bar did not resize alongside the countdown text.'
    $grid.Rows.Clear()
    Sync-DashboardRunBars
    Require ($runBar.IsDisposed -and $active.IsDisposed) 'Deleting the row must dispose both renderer and WPF fallback.'
    Write-Host 'WebView2 failure recovery, responsive cell positioning and lifecycle PASS.'
} finally {
    $form.Close();$form.Dispose()
    if($script:aeroHealthTimer){$script:aeroHealthTimer.Stop();$script:aeroHealthTimer.Dispose()}
}
Assert-NoUnhandledWinFormsErrors
