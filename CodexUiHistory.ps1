# Application-specific, read-only presentation of persisted job outcomes.
function Show-CodexRunHistoryDialog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Form]$Owner,
          [Parameter(Mandatory)][string]$Directory,
          [object[]]$RecentTasks=@(),
          [string]$SelectedName='')
    $dialog=[System.Windows.Forms.Form]::new()
    $dialog.Text='Recent Codex run results'
    $dialog.StartPosition='CenterParent'
    $dialog.ClientSize=[Drawing.Size]::new(960,580)
    $dialog.MinimumSize=[Drawing.Size]::new(760,460)

    # A selected result shows the actual final Codex answer, not merely the
    # Task Scheduler exit status. The second tab exposes local worker evidence.
    $split=[System.Windows.Forms.SplitContainer]::new()
    $split.Dock='Fill'
    $split.Orientation=[System.Windows.Forms.Orientation]::Horizontal
    $dialog.Controls.Add($split)
    $split.Size=$dialog.ClientSize
    $split.SplitterDistance=270

    $grid=[System.Windows.Forms.DataGridView]::new()
    $grid.Dock='Fill'
    $grid.ReadOnly=$true
    $grid.AllowUserToAddRows=$false
    $grid.AllowUserToDeleteRows=$false
    $grid.RowHeadersVisible=$false
    $grid.MultiSelect=$false
    $grid.SelectionMode='FullRowSelect'
    $grid.AutoSizeColumnsMode='Fill'
    foreach($column in @(@('When','Finished (local)'),@('Status','Result'),@('ExitCode','Exit'),@('Attempt','Attempt'),@('NextJob','Next task'),@('Message','Details'))){
        [void]$grid.Columns.Add($column[0],$column[1])
    }
    $grid.Columns['When'].FillWeight=150
    $grid.Columns['Status'].FillWeight=95
    $grid.Columns['ExitCode'].FillWeight=48
    $grid.Columns['Attempt'].FillWeight=68
    $grid.Columns['NextJob'].FillWeight=190
    $grid.Columns['Message'].FillWeight=295
    $split.Panel1.Controls.Add($grid)

    $tabs=[System.Windows.Forms.TabControl]::new()
    $tabs.Dock='Fill'
    $responseTab=[System.Windows.Forms.TabPage]::new('Codex response')
    $logTab=[System.Windows.Forms.TabPage]::new('Worker log')
    $responseBox=[System.Windows.Forms.TextBox]::new()
    $logBox=[System.Windows.Forms.TextBox]::new()
    foreach($box in @($responseBox,$logBox)){
        $box.Dock='Fill'
        $box.Multiline=$true
        $box.ReadOnly=$true
        $box.ScrollBars='Both'
        $box.WordWrap=$false
        $box.Font=[System.Drawing.Font]::new('Consolas',10)
    }
    $responseBox.Text='Select a run to inspect its Codex response.'
    $logBox.Text='Select a run to inspect its worker transcript.'
    $responseTab.Controls.Add($responseBox)
    $logTab.Controls.Add($logBox)
    [void]$tabs.TabPages.Add($responseTab)
    [void]$tabs.TabPages.Add($logTab)
    $split.Panel2.Controls.Add($tabs)

    try {
        $known=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($entry in @(Get-CodexRunHistory -Directory $Directory -Limit 100)){
            [void]$known.Add([string]$entry.Name)
            $row=$grid.Rows.Add($entry.When.ToString('yyyy-MM-dd HH:mm'),$entry.Status,
                $(if($null -eq $entry.ExitCode){''}else{[string]$entry.ExitCode}),
                $(if($null -eq $entry.Attempt){''}else{[string]$entry.Attempt}),
                $entry.NextJob,$entry.Message)
            $grid.Rows[$row].Tag=$entry.Name
            $grid.Rows[$row].Cells['NextJob'].ToolTipText=[string]$entry.NextJob
        }
        foreach($task in @($RecentTasks | Sort-Object When -Descending)){
            if(-not $task.Name -or $known.Contains([string]$task.Name)) { continue }
            if($task.Status -in @('Running','Scheduled')) { continue }
            $row=$grid.Rows.Add($task.When.ToString('yyyy-MM-dd HH:mm'),[string]$task.Status,
                '', '', '', 'Windows Task Scheduler record; no saved worker outcome available here.')
            $grid.Rows[$row].Tag=[string]$task.Name
            $grid.Rows[$row].Cells['Message'].ToolTipText=[string]$task.Description
        }
        $grid.Add_SelectionChanged({
            if($grid.SelectedRows.Count -ne 1){return}
            $name=[string]$grid.SelectedRows[0].Tag
            $evidence=Get-CodexRunEvidence -Directory $Directory -Name $name
            $responseBox.Text=[string]$evidence.Response
            $logBox.Text=[string]$evidence.Transcript
        })
        if($grid.Rows.Count -eq 0){
            $dialog.Text+=' (no results yet)'
        } else {
            $grid.ClearSelection()
            $selectedRow=$grid.Rows[0]
            if($SelectedName){
                foreach($candidate in $grid.Rows){
                    if([string]$candidate.Tag -ceq $SelectedName){$selectedRow=$candidate;break}
                }
            }
            $grid.CurrentCell=$selectedRow.Cells[0]
            $selectedRow.Selected=$true
            $evidence=Get-CodexRunEvidence -Directory $Directory -Name ([string]$selectedRow.Tag)
            $responseBox.Text=[string]$evidence.Response
            $logBox.Text=[string]$evidence.Transcript
        }
        [void]$dialog.ShowDialog($Owner)
    } finally {$dialog.Dispose()}
}
