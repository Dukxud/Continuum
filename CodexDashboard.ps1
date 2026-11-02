Import-Module (Join-Path $PSScriptRoot 'components/Countdown/Countdown.psm1') -Force -ErrorAction Stop
# Dashboard views. Approved Aero v3 bars use WebView2, with WPF fallback.

# UI names preserved while calculations live in the reusable Countdown API.
function Get-RunCountdownText {
    param([datetime]$When,[datetime]$Now)
    return Get-CountdownText -DueAt $When -Now $Now
}
function Get-RunDisplayText {
    param($Item,[datetime]$Now)
    if ($Item.Status -and [string]$Item.Status -ne 'Scheduled') { return [string]$Item.Status }
    return Get-RunCountdownText $Item.When $Now
}
function Get-RunCountdownPercent {
    param([datetime]$When,$CreatedAt,[datetime]$Now)
    return Get-CountdownElapsedPercent -DueAt $When -CreatedAt $CreatedAt -Now $Now
}

function Get-DashboardUsageModel {
    if ($script:ui.Dashboard.compactToggle -and $script:ui.Dashboard.compactToggle.Checked -and $script:ui.Dashboard.pendingSnapshot.Count -gt 0) {
        $selected = $script:ui.Dashboard.pendingSnapshot[0]
        $nextModel = if (-not $selected.Status -or $selected.Status -in @('Scheduled','Running')) { [string]$selected.Model } else { '' }
        if ($nextModel -match '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$') { return $nextModel }
    }
    return Get-SelectedModel
}

function New-DashboardLabel {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height)
    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.Location = [System.Drawing.Point]::new($X,$Y)
    $label.Size = [System.Drawing.Size]::new($Width,$Height)
    $label.AutoEllipsis = $true
    $Parent.Controls.Add($label)
    return $label
}

function Initialize-Dashboard {
    # Capture the old full-view controls before adding the compact-only controls.
    $shared = @($heading,$usageHeading,$usageNotice,$usageCards[0].Panel,$usageCards[1].Panel)
    $script:ui.Dashboard.dashboardStandardOnly = @($form.Controls | Where-Object { $shared -notcontains $_ })
    $script:ui.Dashboard.fullTitleFont = $heading.Font
    $script:ui.Dashboard.compactTitleFont = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
    $script:ui.Dashboard.countdownBlue = [System.Drawing.Color]::FromArgb(49,95,167)

    # A high-contrast, button-style toggle in a reserved header location.
    # The former small checkbox overlapped the subtitle and compact title.
    $script:ui.Dashboard.compactToggle = [System.Windows.Forms.CheckBox]::new()
    $script:ui.Dashboard.compactToggle.Appearance = [System.Windows.Forms.Appearance]::Button
    $script:ui.Dashboard.compactToggle.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $script:ui.Dashboard.compactToggle.FlatAppearance.BorderSize = 1
    $script:ui.Dashboard.compactToggle.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $script:ui.Dashboard.compactToggle.TextAlign = 'MiddleCenter'
    $script:ui.Dashboard.compactToggle.Location = [System.Drawing.Point]::new(728,13)
    $script:ui.Dashboard.compactToggle.Size = [System.Drawing.Size]::new(170,38)
    $script:ui.Dashboard.compactToggle.AccessibleName = 'Toggle compact mode'
    $script:ui.Dashboard.compactToggle.Checked = ($script:ui.Preferences.uiSettings -and $script:ui.Preferences.uiSettings.compactMode -eq $true)
    $form.Controls.Add($script:ui.Dashboard.compactToggle)
    $script:ui.Dashboard.compactToggle.BringToFront()

    # Appearance controls remain accessible in both standard and compact layouts.
    $script:ui.Dashboard.appearanceButton = [System.Windows.Forms.Button]::new()
    $script:ui.Dashboard.appearanceButton.Text = 'Appearance...'
    $script:ui.Dashboard.appearanceButton.AccessibleName = 'Customize progress bar appearance'
    $script:ui.Dashboard.appearanceButton.Size = [System.Drawing.Size]::new(140,32)
    $form.Controls.Add($script:ui.Dashboard.appearanceButton)
    $script:ui.Dashboard.appearanceButton.Add_Click({ Show-AeroAppearanceDialog $form })

    $script:ui.Dashboard.compactRunHeading = New-DashboardLabel $form 'Next run' 18 61 425 26
    $script:ui.Dashboard.compactRunHeading.Font = [System.Drawing.Font]::new('Segoe UI',11,[System.Drawing.FontStyle]::Bold)
    $script:ui.Dashboard.compactRunPanel = [System.Windows.Forms.Panel]::new()
    $script:ui.Dashboard.compactRunPanel.Location = [System.Drawing.Point]::new(18,91)
    $script:ui.Dashboard.compactRunPanel.Size = [System.Drawing.Size]::new(428,129)
    $script:ui.Dashboard.compactRunPanel.BackColor = [System.Drawing.Color]::FromArgb(246,249,253)
    $script:ui.Dashboard.compactRunPanel.BorderStyle = 'FixedSingle'
    $form.Controls.Add($script:ui.Dashboard.compactRunPanel)

    $script:ui.Dashboard.compactRunName = New-DashboardLabel $script:ui.Dashboard.compactRunPanel '' 14 12 240 27
    $script:ui.Dashboard.compactRunName.Font = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
    $script:ui.Dashboard.compactRunEta = New-DashboardLabel $script:ui.Dashboard.compactRunPanel '' 251 12 160 27
    $script:ui.Dashboard.compactRunEta.TextAlign = 'MiddleRight'
    $script:ui.Dashboard.compactRunEta.Font = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
    $script:ui.Dashboard.compactRunEta.ForeColor = $script:ui.Dashboard.countdownBlue
    $script:ui.Dashboard.compactRunDetails = New-DashboardLabel $script:ui.Dashboard.compactRunPanel '' 14 42 395 24
    $script:ui.Dashboard.compactRunDetails.ForeColor = [System.Drawing.Color]::DimGray
    $script:ui.Dashboard.compactRunDate = New-DashboardLabel $script:ui.Dashboard.compactRunPanel '' 14 70 395 23
    $script:ui.Dashboard.compactRunDate.ForeColor = [System.Drawing.Color]::DimGray

    $script:ui.Dashboard.compactRunTrack = New-AeroProgressBar $script:ui.Dashboard.compactRunPanel 14 101 396 17 'time'

    $script:ui.Dashboard.compactUsageModel = New-DashboardLabel $form '' 232 240 210 26
    $script:ui.Dashboard.compactUsageModel.ForeColor = [System.Drawing.Color]::DimGray
    $script:ui.Dashboard.compactUsageModel.TextAlign = 'MiddleRight'
    $script:ui.Dashboard.compactUsageStatus = New-DashboardLabel $form 'Reading usage limits...' 18 85 426 32
    $script:ui.Dashboard.compactUsageStatus.ForeColor = [System.Drawing.Color]::DimGray

    # A separate, non-networked timer updates only displayed countdowns.
    $script:ui.Dashboard.countdownTimer = [System.Windows.Forms.Timer]::new()
    $script:ui.Dashboard.countdownTimer.Interval = 1000
    $script:ui.Dashboard.countdownTimer.Add_Tick({ Update-DashboardCountdowns })

    # One modest activity strip belongs to both layouts. The spinner means
    # Windows confirms a Running task; it is not an execution percentage.
    $activity=[System.Windows.Forms.Panel]::new()
    $activity.Size=[System.Drawing.Size]::new(880,29)
    $activity.BackColor=[System.Drawing.Color]::FromArgb(240,245,251)
    $form.Controls.Add($activity)
    $script:ui.Dashboard.activityPanel=$activity
    $indicator=[System.Windows.Forms.Panel]::new()
    $indicator.Size=[System.Drawing.Size]::new(26,26)
    $indicator.Location=[System.Drawing.Point]::new(4,1)
    $indicator.Visible=$false
    $indicator.Add_Paint({
        param($sender,$e)
        $e.Graphics.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        for($i=0;$i -lt 8;$i++){
            $age=($script:ui.Dashboard.activityFrame-$i+8)%8
            $alpha=[int](42+213*(8-$age)/8)
            $angle=$i*[math]::PI/4.0
            $x=[single](11+8*[math]::Cos($angle))
            $y=[single](11+8*[math]::Sin($angle))
            $brush=[System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($alpha,48,100,173))
            try {$e.Graphics.FillEllipse($brush,$x,$y,[single]4,[single]4)}
            finally {$brush.Dispose()}
        }
    })
    $activity.Controls.Add($indicator)
    $script:ui.Dashboard.activitySpinner=$indicator
    $label=New-DashboardLabel $activity 'No recorded runs yet.' 33 2 820 25
    $label.TextAlign='MiddleLeft'
    $label.ForeColor=[System.Drawing.Color]::FromArgb(48,69,91)
    $script:ui.Dashboard.activityLabel=$label
    $activityTimer=[System.Windows.Forms.Timer]::new()
    $activityTimer.Interval=110
    $activityTimer.Add_Tick({
        $script:ui.Dashboard.activityFrame=($script:ui.Dashboard.activityFrame+1)%8
        $script:ui.Dashboard.activitySpinner.Invalidate()
    })
    $script:ui.Dashboard.activityTimer=$activityTimer

    # Standard view displays the time label in the native grid, with a real
    # WPF progress control below it. The WPF compositor animates without timers.
    $script:ui.Dashboard.runBarHosts = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
    $grid.Add_CellPainting({
        param($sender,$e)
        if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 1) { return }
        $e.PaintBackground($e.CellBounds,$true)
        $cell = $sender.Rows[$e.RowIndex].Cells[1]
        $bounds = [System.Drawing.Rectangle]::new(
            $e.CellBounds.X+8,$e.CellBounds.Y+2,$e.CellBounds.Width-16,23)
        $color = if (($e.State -band [System.Windows.Forms.DataGridViewElementStates]::Selected) -ne 0) {
            $e.CellStyle.SelectionForeColor
        } else { $e.CellStyle.ForeColor }
        [System.Windows.Forms.TextRenderer]::DrawText(
            $e.Graphics,[string]$cell.Value,$sender.Font,$bounds,$color,
            [System.Windows.Forms.TextFormatFlags]::VerticalCenter)
        $e.Paint($e.CellBounds,[System.Windows.Forms.DataGridViewPaintParts]::Border)
        $e.Handled = $true
    })
    $grid.Add_Scroll({ Sync-DashboardRunBars })
    $grid.Add_ColumnWidthChanged({ Sync-DashboardRunBars })
    $grid.Add_SizeChanged({ Sync-DashboardRunBars })
    $grid.Add_VisibleChanged({ Sync-DashboardRunBars })

    $script:ui.Dashboard.compactToggle.Add_CheckedChanged({
        Update-DashboardLayout
        Queue-FormStateSave
        if ((Get-DashboardUsageModel) -ne [string]$script:ui.Usage.usageRequestedModel) { Request-UsageRefresh }
    })
}

function Sync-DashboardRunBars {
    # Browser-backed views are expensive. Keep one live bar for each visible
    # grid cell, not one hidden WebView2 per scheduled job.
    $hosts=$script:ui.Dashboard.runBarHosts
    if ($null -eq $hosts -or $grid.Columns.Count -lt 2) { return }
    $visible=[Collections.Generic.List[object]]::new()
    if($grid.Visible -and $grid.Rows.Count -gt 0 -and $grid.FirstDisplayedScrollingRowIndex -ge 0){
        $first=$grid.FirstDisplayedScrollingRowIndex
        $last=[math]::Min($grid.Rows.Count-1,$first + [math]::Max(0,$grid.DisplayedRowCount($true)))
        for($rowIndex=$first;$rowIndex -le $last;$rowIndex++){
            if(-not $grid.Rows[$rowIndex].Visible){continue}
            # Completed runs show a result, never a countdown bar.
            if($grid.Rows[$rowIndex].Cells[1].Tag -eq 'history'){continue}
            $cell=$grid.GetCellDisplayRectangle(1,$rowIndex,$true)
            if($cell.Width -gt 32 -and $cell.Height -ge 22){
                $visible.Add([pscustomobject]@{ Row=$rowIndex; Cell=$cell })
            }
        }
    }
    while($hosts.Count -gt $visible.Count){
        $index=$hosts.Count-1
        Remove-AeroProgressBar $hosts[$index]
        $hosts.RemoveAt($index)
    }
    while($hosts.Count -lt $visible.Count){
        $hosts.Add((New-AeroProgressBar $grid 0 0 100 15 'time'))
    }
    for($index=0;$index -lt $visible.Count;$index++){
        $entry=$visible[$index]
        $bar=$hosts[$index]
        $cell=$entry.Cell
        $bounds=[System.Drawing.Rectangle]::new($cell.X+8,$cell.Bottom-19,$cell.Width-16,15)
        Set-ProgressHostLayout -Primary $bar -Bounds $bounds -Visible $true
        Set-AeroProgress $bar $grid.Rows[$entry.Row].Cells[1].Tag
    }
}

function Update-DashboardCountdowns {
    $now = Get-Date
    $lookup=$script:ui.Dashboard.pendingIndex
    foreach ($row in @($grid.Rows)) {
        $name=[string]$row.Tag
        if (-not $name -or -not $lookup.ContainsKey($name)) { continue }
        $item=$lookup[$name]
        $cell = $row.Cells[1]
        $label = Get-RunDisplayText $item $now
        $percent = if (-not $item.Status -or $item.Status -eq 'Scheduled') { Get-RunCountdownPercent $item.When $item.CreatedAt $now } else { $null }
        if ($cell.Value -cne $label -or $cell.Tag -ne $percent) {
            $cell.Value = $label
            $cell.Tag = $percent
            $grid.InvalidateCell($cell)
        }
    }
    Sync-DashboardRunBars
    if (-not $script:ui.Dashboard.compactToggle.Checked -or $script:ui.Dashboard.pendingSnapshot.Count -eq 0) { return }
    $next = $script:ui.Dashboard.pendingSnapshot[0]
    $root = ([string]$next.Repo).TrimEnd([char[]]@('/','\'))
    $script:ui.Dashboard.compactRunName.Text = if ($root -and $root -ne '-') { [IO.Path]::GetFileName($root) } else { 'Scheduled Codex run' }
    $script:ui.Dashboard.compactRunHeading.Text = if ($next.Status -eq 'Running') { 'Running now' } elseif (-not $next.Status -or $next.Status -eq 'Scheduled') { 'Next run' } else { 'Recent run' }
    $script:ui.Dashboard.compactRunEta.Text = Get-RunDisplayText $next $now
    $script:ui.Dashboard.compactRunDetails.Text = [string]$next.Description
    $script:ui.Dashboard.compactRunDate.Text = 'Scheduled ' + $next.When.ToString('ddd MMM d, h:mm tt')
    $percent = if (-not $next.Status -or $next.Status -eq 'Scheduled') { Get-RunCountdownPercent $next.When $next.CreatedAt $now } else { $null }
    Set-AeroProgress $script:ui.Dashboard.compactRunTrack $percent
    $script:ui.Dashboard.compactRunTrack.AccessibleName = $script:ui.Dashboard.compactRunEta.Text + $(if ($null -ne $percent) { ", $percent% of time to scheduled trigger elapsed" } else { ', no execution-progress estimate' })
}


function Update-DashboardActivity {
    param([object[]]$Items,[string]$Directory)
    $indicator=$script:ui.Dashboard.activitySpinner
    $label=$script:ui.Dashboard.activityLabel
    $timer=$script:ui.Dashboard.activityTimer
    $running=@($Items | Where-Object { $_.Status -eq 'Running' })
    if($running.Count -gt 0){
        $target=$running[0]
        $repo=[string]$target.Repo
        $project=if($repo -and $repo -ne '-') {[IO.Path]::GetFileName($repo.TrimEnd([char[]]@('/','\')))} else {'scheduled continuation'}
        $label.Text='Codex running: '+$project+' — execution in progress'
        $label.AccessibleName=$label.Text
        $indicator.Visible=$true
        $timer.Start()
        return
    }
    $timer.Stop()
    $indicator.Visible=$false
    $latest=@(Get-CodexRunHistory -Directory $Directory -Limit 1)
    if($latest.Count -eq 0){
        $label.Text='No recorded runs yet. Use Recent results to inspect past runs.'
        $label.AccessibleName=$label.Text
        return
    }
    $result=$latest[0]
    $key=[string]$result.Name+'|'+$result.When.ToString('o')
    if($script:ui.Dashboard.latestResultKey -cne $key){
        $evidence=Get-CodexRunEvidence -Directory $Directory -Name ([string]$result.Name)
        $preview=([string]$evidence.Response -replace '[\r\n\t]+',' ').Trim()
        if($preview -eq 'No final Codex response was recorded for this run.' -and $result.Message){
            $preview=[string]$result.Message
        }
        $script:ui.Dashboard.latestResultPreview=$preview
        $script:ui.Dashboard.latestResultKey=$key
    }
    $summary='Latest: '+([string]$result.Status).ToUpperInvariant()+' — '+[string]$result.Name
    $preview=[string]$script:ui.Dashboard.latestResultPreview
    if($preview){$summary+=' — '+$preview}
    $label.Text=$summary
    $label.AccessibleName=$summary
}

function Update-DashboardLayout {
    $compact = $script:ui.Dashboard.compactToggle.Checked
    foreach ($control in $script:ui.Dashboard.dashboardStandardOnly) { $control.Visible = -not $compact }
    $script:ui.Dashboard.compactRunHeading.Visible = $compact -and $script:ui.Dashboard.pendingSnapshot.Count -gt 0
    $script:ui.Dashboard.compactRunPanel.Visible = $script:ui.Dashboard.compactRunHeading.Visible
    $script:ui.Dashboard.compactUsageModel.Visible = $false
    $script:ui.Dashboard.compactUsageStatus.Visible = $false
    if (-not $compact) {
        $heading.Text = 'Schedule a continuation'
        $heading.Font = $script:ui.Dashboard.fullTitleFont
        $heading.Width = 500
        $script:ui.Dashboard.appearanceButton.Location = [System.Drawing.Point]::new(574,15)
        $script:ui.Dashboard.compactToggle.Location = [System.Drawing.Point]::new(728,13)
        $script:ui.Dashboard.compactToggle.Size = [System.Drawing.Size]::new(170,38)
        $script:ui.Dashboard.compactToggle.Text = 'Compact mode: OFF'
        $script:ui.Dashboard.compactToggle.BackColor = [System.Drawing.Color]::FromArgb(236,242,250)
        $script:ui.Dashboard.compactToggle.ForeColor = [System.Drawing.Color]::FromArgb(40,76,128)
        $script:ui.Dashboard.compactToggle.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(163,189,219)
        $subtitle.Visible = $false
        $usageHeading.Text = 'Usage remaining'
        $usageHeading.Location = [System.Drawing.Point]::new(18,322)
        $usageNotice.Visible = $true
        $usageNotice.Location = [System.Drawing.Point]::new(18,477)
        foreach ($i in 0..1) {
            $usageCards[$i].Panel.Visible = $true
            $usageCards[$i].Panel.Location = [System.Drawing.Point]::new($(if ($i -eq 0) { 18 } else { 470 }),358)
        }
        $hasRuns = $script:ui.Dashboard.displayedRunCount -gt 0
        foreach ($control in @($separator2,$pending,$grid,$refreshRuns,$cancelRun,$viewResult)) { $control.Visible = $hasRuns }
        $openFolder.Location = [System.Drawing.Point]::new($(if ($hasRuns) { 352 } else { 18 }),$(if ($hasRuns) { 774 } else { 523 }))
        $recentResults.Location = [System.Drawing.Point]::new($(if ($hasRuns) { 520 } else { 185 }),$(if ($hasRuns) { 774 } else { 523 }))
        $recentResults.Visible = $true
        $viewResult.Location = [System.Drawing.Point]::new(693,774)
        $script:ui.Dashboard.activityPanel.Location = [System.Drawing.Point]::new(18,$(if ($hasRuns) { 817 } else { 574 }))
        $script:ui.Dashboard.activityPanel.Size = [System.Drawing.Size]::new(880,29)
        $script:ui.Dashboard.activityLabel.Width = 840
        $status.Location = [System.Drawing.Point]::new(18,$(if ($hasRuns) { 853 } else { 610 }))
        $form.MinimumSize = [System.Drawing.Size]::new(940,$(if ($hasRuns) { 933 } else { 690 }))
        $form.ClientSize = [System.Drawing.Size]::new(920,$(if ($hasRuns) { 922 } else { 680 }))
        Sync-DashboardRunBars
        return
    }

    $heading.Text = 'Codex Scheduler'
    $heading.Font = $script:ui.Dashboard.compactTitleFont
    $heading.Width = 270
    $script:ui.Dashboard.compactToggle.Location = [System.Drawing.Point]::new(298,13)
    $script:ui.Dashboard.compactToggle.Size = [System.Drawing.Size]::new(148,38)
    $script:ui.Dashboard.compactToggle.Text = 'Compact mode: ON'
    $script:ui.Dashboard.compactToggle.BackColor = [System.Drawing.Color]::FromArgb(49,95,167)
    $script:ui.Dashboard.compactToggle.ForeColor = [System.Drawing.Color]::White
    $script:ui.Dashboard.compactToggle.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(36,73,130)
    $usageNotice.Visible = $false
    $top = if ($script:ui.Dashboard.pendingSnapshot.Count -gt 0) { 246 } else { 65 }
    $visibleWindows = @()
    $targetModel = Get-DashboardUsageModel
    $currentSnapshot = $script:ui.Usage.usageSnapshot -and (-not $targetModel -or $script:ui.Usage.usageSnapshotRequestedModel -ceq $targetModel)
    if ($currentSnapshot -and -not $script:ui.Usage.usageReadFailed) {
        $visibleWindows = @($script:ui.Usage.usageSnapshot.windows | Where-Object { $null -ne $_ })
    }
    if ($visibleWindows.Count -eq 0) {
        $usageHeading.Visible = $false
        $script:ui.Dashboard.compactUsageStatus.Text = if ($script:ui.Usage.usageReadFailed -or $currentSnapshot) { 'Usage limits unavailable' } else { 'Reading usage limits...' }
        $script:ui.Dashboard.compactUsageStatus.Location = [System.Drawing.Point]::new(18,$top)
        $script:ui.Dashboard.compactUsageStatus.Visible = $true
        foreach ($card in $usageCards) { $card.Panel.Visible = $false }
        $height = $top + 52
    } else {
        $usageHeading.Text = 'Usage limits'
        $usageHeading.Location = [System.Drawing.Point]::new(18,$top)
        $usageHeading.Visible = $true
        $script:ui.Dashboard.compactUsageModel.Location = [System.Drawing.Point]::new(225,$top)
        $script:ui.Dashboard.compactUsageModel.Text = [string]$script:ui.Usage.usageSnapshot.model
        $script:ui.Dashboard.compactUsageModel.Visible = $true
        $cardTop = $top + 34
        foreach ($i in 0..1) {
            $visible = $i -lt $visibleWindows.Count
            $usageCards[$i].Panel.Visible = $visible
            if ($visible) {
                $usageCards[$i].Panel.Location = [System.Drawing.Point]::new(18,$cardTop)
                $cardTop += 117
            }
        }
        $height = $cardTop + 18
    }
    $form.MinimumSize = [System.Drawing.Size]::new(480,150)
    # Keep live activity and latest result visible even in compact mode.
    $script:ui.Dashboard.activityPanel.Location = [System.Drawing.Point]::new(18,$height)
    $script:ui.Dashboard.activityPanel.Size = [System.Drawing.Size]::new(428,29)
    $script:ui.Dashboard.activityLabel.Width = 388
    $form.ClientSize = [System.Drawing.Size]::new(464,[math]::Max(166,$height+78))
    $script:ui.Dashboard.appearanceButton.Location = [System.Drawing.Point]::new(306,$form.ClientSize.Height-37)
    $recentResults.Location = [System.Drawing.Point]::new(150,$form.ClientSize.Height-37)
    $recentResults.Visible = $true
    $script:ui.Dashboard.appearanceButton.Size = [System.Drawing.Size]::new(140,32)
    Update-DashboardCountdowns
    Sync-DashboardRunBars
}
