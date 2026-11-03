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

function Get-RunLabelWidth {
    param([string]$Text,[System.Drawing.Font]$Font,[int]$CellWidth)
    # Measure the actual countdown/status text instead of reserving a wide
    # fixed slot before the bar. Leave a small allowance for native text edges.
    # The overload without an IDeviceContext ignores NoPadding; use its
    # supported default metrics in both text painting and bar placement.
    $measured=[System.Windows.Forms.TextRenderer]::MeasureText(
        $Text,$Font,[System.Drawing.Size]::new(10000,32)).Width
    return [math]::Min([math]::Max(24,[int]($CellWidth*.52)),[math]::Max(24,$measured+8))
}

function Get-UpcomingGridHeight {
    param([System.Windows.Forms.DataGridView]$Grid)
    # One through four real rows; beyond that use the grid's native scroll.
    $visibleCount=[math]::Min(4,[math]::Max(1,$Grid.Rows.Count))
    $rowPixels=0
    for($i=0;$i -lt $visibleCount;$i++){
        $rowPixels+=if($i -lt $Grid.Rows.Count){$Grid.Rows[$i].Height}else{$Grid.RowTemplate.Height}
    }
    return $Grid.ColumnHeadersHeight+$rowPixels+3
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
    $shared = @($heading,$usageHeading,$status,$usageCards[0].Panel,$usageCards[1].Panel)
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

    # Standard view uses a single horizontal line: time text and Aero track
    # side by side. Never stack an execution percentage beneath Running.
    $script:ui.Dashboard.runBarHosts = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
    $grid.Add_CellPainting({
        param($sender,$e)
        if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 1) { return }
        $e.PaintBackground($e.CellBounds,$true)
        $cell = $sender.Rows[$e.RowIndex].Cells[1]
        $labelWidth=Get-RunLabelWidth -Text ([string]$cell.Value) -Font $sender.Font -CellWidth $e.CellBounds.Width
        $bounds = [System.Drawing.Rectangle]::new(
            $e.CellBounds.X+6,$e.CellBounds.Y+2,$labelWidth,$e.CellBounds.Height-4)
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
        if ((Get-DashboardUsageModel) -ne [string]$script:ui.Usage.usageRequestedModel) { Request-SystemRefresh -Scope ModelChanged }
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
        $labelWidth=Get-RunLabelWidth -Text ([string]$grid.Rows[$entry.Row].Cells[1].Value) -Font $grid.Font -CellWidth $cell.Width
        $barX=$cell.X+6+$labelWidth+6
        $bounds=[System.Drawing.Rectangle]::new($barX,$cell.Y+[int](($cell.Height-15)/2),[math]::Max(20,$cell.Right-$barX-9),15)
        Set-ProgressHostLayout -Primary $bar -Bounds $bounds -Visible $true
        $row=$grid.Rows[$entry.Row]
        $taskName=[string]$row.Tag
        $task=if($script:ui.Dashboard.pendingIndex.ContainsKey($taskName)){$script:ui.Dashboard.pendingIndex[$taskName]}else{$null}
        if($task -and $task.Status -eq 'Running'){Set-AeroWorking $bar}
        else{Set-AeroProgress $bar $row.Cells[1].Tag}
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
    if($next.Status -eq 'Running'){
        Set-AeroWorking $script:ui.Dashboard.compactRunTrack
        $script:ui.Dashboard.compactRunTrack.AccessibleName='Codex working; completion unknown'
    }else{
        Set-AeroProgress $script:ui.Dashboard.compactRunTrack $percent
        $script:ui.Dashboard.compactRunTrack.AccessibleName=$script:ui.Dashboard.compactRunEta.Text + ", $percent% of time to scheduled trigger elapsed"
    }
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
        $usageHeading.Text = 'Usage remaining'
        $usageHeading.Location = [System.Drawing.Point]::new(18,322)
        foreach ($i in 0..1) {
            $usageCards[$i].Panel.Visible = $true
            $usageCards[$i].Panel.Location = [System.Drawing.Point]::new($(if ($i -eq 0) { 18 } else { 470 }),358)
        }
        $hasRuns = $script:ui.Dashboard.pendingSnapshot.Count -gt 0
        foreach ($control in @($separator2,$pending,$grid,$cancelRun)) { $control.Visible = $hasRuns }
        $actionTop=490
        $clientHeight=566
        $minimumHeight=595
        if($hasRuns){
            $desiredGridHeight=Get-UpcomingGridHeight -Grid $grid
            if($grid.Height -ne $desiredGridHeight){$grid.Height=$desiredGridHeight}
            $actionTop=$grid.Bottom+13
            $offset=744-$actionTop
            $clientHeight=820-$offset
            $minimumHeight=845-$offset
            $cancelRun.Location=[System.Drawing.Point]::new(18,$actionTop)
        }
        $openFolder.Location=[System.Drawing.Point]::new($(if($hasRuns){185}else{18}),$actionTop)
        $recentResults.Location=[System.Drawing.Point]::new($(if($hasRuns){352}else{185}),$actionTop)
        $recentResults.Visible=$true
        $status.Location=[System.Drawing.Point]::new(18,$(if($hasRuns){$actionTop+39}else{526}))
        $status.Width=880
        $status.Visible=-not [string]::IsNullOrWhiteSpace([string]$script:ui.Preferences.alertMessage)
        $form.MinimumSize=[System.Drawing.Size]::new(940,$minimumHeight)
        $form.ClientSize=[System.Drawing.Size]::new(920,$clientHeight)
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
    $top = if ($script:ui.Dashboard.pendingSnapshot.Count -gt 0) { 246 } else { 65 }
    $visibleWindows = @()
    $targetModel = Get-DashboardUsageModel
    $currentSnapshot = $script:ui.Usage.usageSnapshot -and (-not $targetModel -or $script:ui.Usage.usageSnapshotRequestedModel -ceq $targetModel)
    if ($currentSnapshot) {
        # Failed refresh already replaced the card values with Unavailable;
        # retain the cards rather than showing a detached compact disclaimer.
        $visibleWindows = @($script:ui.Usage.usageSnapshot.windows | Where-Object { $null -ne $_ })
    }
    if ($script:ui.Usage.usageReadFailed -and $visibleWindows.Count -eq 0) {
        $visibleWindows = @([pscustomobject]@{}) # show the existing unavailable card
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
    # A warning appears only when necessary, never as a persistent footer.
    $hasAlert=-not [string]::IsNullOrWhiteSpace([string]$script:ui.Preferences.alertMessage)
    $status.Visible=$hasAlert
    $status.Location=[System.Drawing.Point]::new(18,$height)
    $status.Width=428
    $form.ClientSize=[System.Drawing.Size]::new(464,[math]::Max(166,$height+40+$(if($hasAlert){31}else{0})))
    # Right-align the compact actions with a visible gap at every compact height.
    $appearanceLeft = $form.ClientSize.Width - 18 - $script:ui.Dashboard.appearanceButton.Width
    $recentLeft = $appearanceLeft - 12 - $recentResults.Width
    $actionTop = $form.ClientSize.Height - 37
    $script:ui.Dashboard.appearanceButton.Location = [System.Drawing.Point]::new($appearanceLeft,$actionTop)
    $recentResults.Location = [System.Drawing.Point]::new($recentLeft,$actionTop)
    $recentResults.Visible = $true
    Update-DashboardCountdowns
    Sync-DashboardRunBars
}
