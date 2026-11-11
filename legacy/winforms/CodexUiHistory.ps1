# Application-specific, read-only presentation of persisted job outcomes.
function Copy-CodexEvidenceText {
    param([string]$Text)
    if([string]::IsNullOrEmpty($Text)){return}
    [System.Windows.Forms.Clipboard]::SetText($Text)
}
function Show-CodexRunHistoryDialog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Form]$Owner,
          [Parameter(Mandatory)][string]$Directory,
          [object[]]$RecentTasks=@(),
          [string]$SelectedName='')
    $dialog=[System.Windows.Forms.Form]::new()
    $dialog.Text='Recent Codex runs'
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

    $historyGrid=[System.Windows.Forms.DataGridView]::new()
    $historyGrid.Dock='Fill'
    $historyGrid.ReadOnly=$true
    $historyGrid.AllowUserToAddRows=$false
    $historyGrid.AllowUserToDeleteRows=$false
    $historyGrid.RowHeadersVisible=$false
    $historyGrid.MultiSelect=$false
    $historyGrid.SelectionMode='FullRowSelect'
    $historyGrid.AutoSizeColumnsMode='Fill'
    foreach($column in @(@('When','Finished (local)'),@('Status','Result'),@('ExitCode','Exit'),@('Attempt','Attempt'),@('NextJob','Next task'),@('Message','Details'))){
        [void]$historyGrid.Columns.Add($column[0],$column[1])
    }
    $historyGrid.Columns['When'].FillWeight=150
    $historyGrid.Columns['Status'].FillWeight=95
    $historyGrid.Columns['ExitCode'].FillWeight=48
    $historyGrid.Columns['Attempt'].FillWeight=68
    $historyGrid.Columns['NextJob'].FillWeight=190
    $historyGrid.Columns['Message'].FillWeight=295
    $split.Panel1.Controls.Add($historyGrid)
    $actionPanel=[System.Windows.Forms.Panel]::new()
    $actionPanel.Dock='Bottom'
    $actionPanel.Height=40
    $removeRecord=[System.Windows.Forms.Button]::new()
    $removeRecord.Text='Remove from history'
    $removeRecord.AccessibleName='Remove selected finished run from history'
    $removeRecord.Size=[Drawing.Size]::new(172,30)
    $removeRecord.Location=[Drawing.Point]::new(8,5)
    $removeRecord.Enabled=$false
    $actionPanel.Controls.Add($removeRecord)
    $copyResponse=[System.Windows.Forms.Button]::new()
    $copyResponse.Text='Copy response'
    $copyResponse.AccessibleName='Copy selected Codex response to clipboard'
    $copyResponse.Bounds=[Drawing.Rectangle]::new(192,5,148,30)
    $copyResponse.Enabled=$false
    $actionPanel.Controls.Add($copyResponse)
    $copyLog=[System.Windows.Forms.Button]::new()
    $copyLog.Text='Copy worker log'
    $copyLog.AccessibleName='Copy selected worker log to clipboard'
    $copyLog.Bounds=[Drawing.Rectangle]::new(352,5,150,30)
    $copyLog.Enabled=$false
    $actionPanel.Controls.Add($copyLog)
    $split.Panel1.Controls.Add($actionPanel)

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
    $copyResponse.Add_Click({
        try{Copy-CodexEvidenceText -Text $responseBox.Text}
        catch{[System.Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'Unable to copy response') | Out-Null}
    })
    $copyLog.Add_Click({
        try{Copy-CodexEvidenceText -Text $logBox.Text}
        catch{[System.Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'Unable to copy worker log') | Out-Null}
    })
    [void]$tabs.TabPages.Add($responseTab)
    [void]$tabs.TabPages.Add($logTab)
    $split.Panel2.Controls.Add($tabs)

    try {
        $hidden=Get-HiddenCodexRunNames -Directory $Directory
        $known=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($entry in @(Get-CodexRunHistory -Directory $Directory -Limit 100)){
            [void]$known.Add([string]$entry.Name)
            $row=$historyGrid.Rows.Add()
            $record=$historyGrid.Rows[$row]
            $record.Cells['When'].Value=$entry.When.ToString('yyyy-MM-dd HH:mm')
            $record.Cells['Status'].Value=[string]$entry.Status
            $record.Cells['ExitCode'].Value=$(if($null -eq $entry.ExitCode){''}else{[string]$entry.ExitCode})
            $record.Cells['Attempt'].Value=$(if($null -eq $entry.Attempt){''}else{[string]$entry.Attempt})
            $record.Cells['NextJob'].Value=[string]$entry.NextJob
            $record.Cells['Message'].Value=[string]$entry.Message
            $record.Tag=[string]$entry.Name
            $historyGrid.Rows[$row].Cells['NextJob'].ToolTipText=[string]$entry.NextJob
        }
        foreach($task in @($RecentTasks | Sort-Object When -Descending)){
            if(-not $task.Name -or $known.Contains([string]$task.Name) -or $hidden.Contains([string]$task.Name)) { continue }
            if($task.Status -in @('Running','Scheduled')) { continue }
            $row=$historyGrid.Rows.Add()
            $record=$historyGrid.Rows[$row]
            $record.Cells['When'].Value=$task.When.ToString('yyyy-MM-dd HH:mm')
            $record.Cells['Status'].Value=[string]$task.Status
            $record.Cells['ExitCode'].Value=''
            $record.Cells['Attempt'].Value=''
            $record.Cells['NextJob'].Value=''
            $record.Cells['Message'].Value='Windows Task Scheduler record; no saved worker outcome available here.'
            $record.Tag=[string]$task.Name
            $historyGrid.Rows[$row].Cells['Message'].ToolTipText=[string]$task.Description
        }
        $historyGrid.Add_SelectionChanged({
            $selected=($historyGrid.SelectedRows.Count -eq 1)
            $removeRecord.Enabled=$selected
            $copyResponse.Enabled=$false
            $copyLog.Enabled=$false
            if(-not $selected){return}
            $name=[string]$historyGrid.SelectedRows[0].Tag
            $evidence=Get-CodexRunEvidence -Directory $Directory -Name $name
            $responseBox.Text=[string]$evidence.Response
            $logBox.Text=[string]$evidence.Transcript
            $copyResponse.Enabled=-not [string]::IsNullOrEmpty($responseBox.Text)
            $copyLog.Enabled=-not [string]::IsNullOrEmpty($logBox.Text)
        })
        $removeRecord.Add_Click({
            if($historyGrid.SelectedRows.Count -ne 1){return}
            $selectedRow=$historyGrid.SelectedRows[0]
            $name=[string]$selectedRow.Tag
            if([System.Windows.Forms.MessageBox]::Show($dialog,
                "Remove '$name' from Recent runs?`n`nThe Windows task and saved Codex logs will not be deleted.",
                'Remove finished run from lists','YesNo','Question') -ne 'Yes'){return}
            try {
                Hide-CodexRunRecord -Directory $Directory -Name $name
                $historyGrid.Rows.Remove($selectedRow)
                $removeRecord.Enabled=($historyGrid.SelectedRows.Count -eq 1)
                if($historyGrid.Rows.Count -eq 0){
                    $responseBox.Text='No results to display.'
                    $logBox.Text='No worker transcript selected.'
                    $copyResponse.Enabled=$false
                    $copyLog.Enabled=$false
                } else {
                    $historyGrid.CurrentCell=$historyGrid.Rows[0].Cells[0]
                    $historyGrid.Rows[0].Selected=$true
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'Unable to remove run') | Out-Null
            }
        })
        if($historyGrid.Rows.Count -eq 0){
            $dialog.Text+=' (no results yet)'
        } else {
            $historyGrid.ClearSelection()
            $selectedRow=$historyGrid.Rows[0]
            if($SelectedName){
                foreach($candidate in $historyGrid.Rows){
                    if([string]$candidate.Tag -ceq $SelectedName){$selectedRow=$candidate;break}
                }
            }
            $historyGrid.CurrentCell=$selectedRow.Cells[0]
            $selectedRow.Selected=$true
            $evidence=Get-CodexRunEvidence -Directory $Directory -Name ([string]$selectedRow.Tag)
            $responseBox.Text=[string]$evidence.Response
            $logBox.Text=[string]$evidence.Transcript
            $copyResponse.Enabled=-not [string]::IsNullOrEmpty($responseBox.Text)
            $copyLog.Enabled=-not [string]::IsNullOrEmpty($logBox.Text)
        }
        [void]$dialog.ShowDialog($Owner)
    } finally {$dialog.Dispose()}
}
