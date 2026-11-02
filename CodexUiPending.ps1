# Upcoming runs only. Past outcomes are displayed in Recent runs.
# Reconcile scheduled/running row identities to prevent refresh flicker.
function Apply-PendingList {
    param([object[]]$Items)
    $upcoming=@($Items | Where-Object { $_.Status -in @('Running','Scheduled') })
    # Legacy Windows task outcomes remain available to the history dialog;
    # persisted results are read directly from the outcome store there.
    $hidden=Get-HiddenCodexRunNames -Directory $appDir
    $script:ui.Dashboard.historySnapshot=@($Items | Where-Object {
        $_.Status -notin @('Running','Scheduled') -and -not $hidden.Contains([string]$_.Name)
    })
    $script:ui.Dashboard.pendingSnapshot=$upcoming
    $pendingIndex=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in $upcoming){if($item.Name){$pendingIndex[[string]$item.Name]=$item}}
    $script:ui.Dashboard.pendingIndex=$pendingIndex

    # Keep rows and their selection if the task identities/order are unchanged.
    # Status and countdown values update in place on each two-second refresh.
    $same=($grid.Rows.Count -eq $upcoming.Count)
    if($same){
        for($i=0;$i -lt $upcoming.Count;$i++){
            if([string]$grid.Rows[$i].Tag -cne [string]$upcoming[$i].Name){$same=$false;break}
        }
    }
    $selected=if($grid.SelectedRows.Count -eq 1){[string]$grid.SelectedRows[0].Tag}else{''}
    $grid.SuspendLayout()
    try {
        if(-not $same){$grid.Rows.Clear()}
        for($i=0;$i -lt $upcoming.Count;$i++){
            $item=$upcoming[$i]
            $path=([string]$item.Repo).TrimEnd([char[]]@('/','\'))
            $project=if($path -and $path -ne '-') {[IO.Path]::GetFileName($path)}else{'Unknown project'}
            $session=if([string]$item.Session -match '^[0-9a-fA-F]{8}-'){([string]$item.Session).Substring(0,8)}else{'-'}
            $when=$item.When.ToString('MMM dd, h:mm tt')
            $details=[string]$item.Description
            if(-not $same){$index=$grid.Rows.Add($when,'',$project,$details,$session)}
            else {$index=$i}
            $row=$grid.Rows[$index]
            $row.Tag=[string]$item.Name
            $row.Cells[0].Value=$when
            $row.Cells[2].Value=$project
            $row.Cells[3].Value=$details
            $row.Cells[4].Value=$session
            $row.Cells[2].ToolTipText=[string]$item.Repo
            $row.Cells[3].ToolTipText=$details
            $row.Cells[4].ToolTipText="Session: $($item.Session)`nTask: $($item.Name)"
            $row.DefaultCellStyle.BackColor=[System.Drawing.Color]::White
            if($row.Cells[1].Tag -eq 'history'){
                $row.Cells[1].Value=''
                $row.Cells[1].Tag=$null
            }
        }
        if(-not $same){
            $grid.ClearSelection()
            if($selected){
                foreach($row in $grid.Rows){
                    if([string]$row.Tag -ceq $selected){
                        $grid.CurrentCell=$row.Cells[0]
                        $row.Selected=$true
                        break
                    }
                }
            }
        }
    } finally {$grid.ResumeLayout()}
    $cancelRun.Enabled=($grid.SelectedRows.Count -eq 1 -and
        $pendingIndex.ContainsKey([string]$grid.SelectedRows[0].Tag) -and
        $pendingIndex[[string]$grid.SelectedRows[0].Tag].Status -eq 'Scheduled')
    $pending.Text="Upcoming runs ($($upcoming.Count))"
    $emptyRuns.Visible=$false
    Update-DashboardActivity -Items $upcoming -Directory $appDir
    Update-DashboardLayout
    Update-DashboardCountdowns
    if($script:ui.Dashboard.compactToggle.Checked -and (Get-DashboardUsageModel) -ne [string]$script:ui.Usage.usageRequestedModel){Request-UsageRefresh}
}
