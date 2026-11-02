# Persistent run projection: active jobs first, followed by the last six
# finished jobs. Refreshes reconcile by job identity to avoid a flashing list.
function Apply-PendingList {
    param([object[]]$Items)
    $upcoming=@($Items | Where-Object { $_.Status -in @('Running','Scheduled') })
    $history=@($Items | Where-Object { $_.Status -notin @('Running','Scheduled') })
    $known=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in @($upcoming)+@($history)){
        if($item.Name){[void]$known.Add([string]$item.Name)}
    }
    # Persisted outcomes remain visible even if Windows removes the task.
    if(-not [string]::IsNullOrWhiteSpace([string]$appDir)){
        foreach($outcome in @(Get-CodexRunHistory -Directory $appDir -Limit 10)){
            if(-not $known.Add([string]$outcome.Name)){continue}
            $payload=Join-Path $appDir ($outcome.Name+'.json')
            $repo='-';$session='-';$description=[string]$outcome.Message
            if(Test-Path -LiteralPath $payload -PathType Leaf){
                try {
                    $job=Get-Content -LiteralPath $payload -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    $repo=[string]$job.repo;$session=[string]$job.sessionId
                    $description=[string]$job.message
                } catch { }
            }
            $history+= [pscustomobject]@{
                Name=$outcome.Name;When=$outcome.When;Repo=$repo;Session=$session
                Description=$description;Model='';CreatedAt=$null
                Status=[string]$outcome.Status
            }
        }
    }
    $history=@($history | Sort-Object When -Descending)
    $recent=@($history | Select-Object -First 6)
    $visible=@($upcoming)+@($recent)
    $script:ui.Dashboard.historySnapshot=$history
    $script:ui.Dashboard.pendingSnapshot=$upcoming
    $script:ui.Dashboard.displayedRunCount=$visible.Count
    $pendingIndex=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $resultIndex=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in $upcoming){if($item.Name){$pendingIndex[[string]$item.Name]=$item}}
    foreach($item in $recent){if($item.Name){$resultIndex[[string]$item.Name]=$item}}
    $script:ui.Dashboard.pendingIndex=$pendingIndex
    $script:ui.Dashboard.resultIndex=$resultIndex

    # Keep rows and their selection if the task identities/order are unchanged.
    # Status and countdown values update in place on each two-second refresh.
    $same=($grid.Rows.Count -eq $visible.Count)
    if($same){
        for($i=0;$i -lt $visible.Count;$i++){
            if([string]$grid.Rows[$i].Tag -cne [string]$visible[$i].Name){$same=$false;break}
        }
    }
    $selected=if($grid.SelectedRows.Count -eq 1){[string]$grid.SelectedRows[0].Tag}else{''}
    $grid.SuspendLayout()
    try {
        if(-not $same){$grid.Rows.Clear()}
        for($i=0;$i -lt $visible.Count;$i++){
            $item=$visible[$i]
            $path=([string]$item.Repo).TrimEnd([char[]]@('/','\'))
            $project=if($path -and $path -ne '-') {[IO.Path]::GetFileName($path)}else{'Unknown project'}
            $session=if([string]$item.Session -match '^[0-9a-fA-F]{8}-'){([string]$item.Session).Substring(0,8)}else{'-'}
            $isHistory=$resultIndex.ContainsKey([string]$item.Name)
            $when=$item.When.ToString('MMM dd, h:mm tt')
            $details=[string]$item.Description
            $runText=if($isHistory){[string]$item.Status}else{''}
            if(-not $same){$index=$grid.Rows.Add($when,$runText,$project,$details,$session)}
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
            if($isHistory){
                $row.Cells[1].Value=$runText
                $row.Cells[1].Tag='history'
                $row.DefaultCellStyle.BackColor=[System.Drawing.Color]::FromArgb(247,249,252)
            }else{
                if($row.Cells[1].Tag -is [string] -and $row.Cells[1].Tag -eq 'history'){
                    $row.Cells[1].Value=''
                    $row.Cells[1].Tag=$null
                }
                $row.DefaultCellStyle.BackColor=[System.Drawing.Color]::White
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
    $viewResult.Enabled=($grid.SelectedRows.Count -eq 1 -and
        $resultIndex.ContainsKey([string]$grid.SelectedRows[0].Tag))
    $pending.Text="Runs ($($upcoming.Count) active, $($recent.Count) recent)"
    $emptyRuns.Visible=$false
    Update-DashboardActivity -Items $upcoming -Directory $appDir
    Update-DashboardLayout
    Update-DashboardCountdowns
    if($script:ui.Dashboard.compactToggle.Checked -and (Get-DashboardUsageModel) -ne [string]$script:ui.Usage.usageRequestedModel){Request-UsageRefresh}
}
