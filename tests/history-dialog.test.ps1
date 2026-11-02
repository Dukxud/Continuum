# Exercise actual result-history dialog through the WinForms message loop.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WinFormsEventGuard.ps1')
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexJobStore.ps1')
. (Join-Path $root 'CodexUiHistory.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('history-dialog-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -Path $temp -ItemType Directory -Force)
$owner=[System.Windows.Forms.Form]::new()
$timer=[System.Windows.Forms.Timer]::new()
$timer.Interval=120
$script:historySeen=$false
$script:historyError=''
$script:historyStart=Get-Date
try {
    [void](Write-JobOutcome -Path (Join-Path $temp 'CodexResume-20260101-1000-abcdef01.result.json') -Status 'completed' -ExitCode 0 -Message 'Complete.')
    [void](Write-JobOutcome -Path (Join-Path $temp 'CodexResume-20260101-1100-abcdef02.result.json') -Status 'deferred' -ExitCode 17 -Attempt 1 -NextJob 'CodexResume-20260101-1200-abcdef03' -Message 'Rescheduled.')
    '{corrupt' | Set-Content -LiteralPath (Join-Path $temp 'CodexResume-20260101-0900-abcdef04.result.json')
    @(
        '{not-json'
        '{"type":"item.completed","item":{"type":"agent_message","text":"SCHEDULER_QA_COMPLETED"}}'
        '{"type":"turn.completed"}'
    ) | Set-Content -LiteralPath (Join-Path $temp 'CodexResume-20260101-1000-abcdef01.jsonl')
    'Codex exit code: 0' | Set-Content -LiteralPath (Join-Path $temp 'CodexResume-20260101-1000-abcdef01.log')
    '{"type":"turn.failed","error":{"message":"Usage limit reached"}}' | Set-Content -LiteralPath (Join-Path $temp 'CodexResume-20260101-1100-abcdef02.jsonl')
    $legacyTask=[pscustomobject]@{
        Name='BP101-Codex-Test';When=(Get-Date).AddMinutes(-30)
        Status='Failed (task exit 1)';Description='Old Windows registration'
    }
    $owner.Show()
    $timer.Add_Tick({
        $dialog=$null
        try {
            $dialog=@([System.Windows.Forms.Application]::OpenForms | Where-Object { $_.Text -like 'Recent Codex run results*' }) | Select-Object -First 1
            if(-not $dialog) {
                if((Get-Date)-gt $script:historyStart.AddSeconds(12)){$script:historyError='History dialog did not open.'}
                return
            }
            $split=@($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.SplitContainer] }) | Select-Object -First 1
            if(-not $split){throw 'History must contain both result list and evidence pane.'}
            $grid=@($split.Panel1.Controls | Where-Object { $_ -is [System.Windows.Forms.DataGridView] }) | Select-Object -First 1
            $tabs=@($split.Panel2.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] }) | Select-Object -First 1
            if(-not $tabs -or $tabs.TabPages.Count -ne 2){throw 'Codex response and worker-log tabs are missing.'}
            $response=@($tabs.TabPages[0].Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] }) | Select-Object -First 1
            $transcript=@($tabs.TabPages[1].Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] }) | Select-Object -First 1
            if(-not $response.ReadOnly -or -not $transcript.ReadOnly){throw 'Evidence must be read-only.'}
            if(-not $grid -or $grid.Rows.Count -ne 4){throw 'History must render persisted outcomes and old Windows task records.'}
            $statuses=@($grid.Rows | ForEach-Object { [string]$_.Cells['Status'].Value })
            foreach($status in @('completed','deferred','unreadable','Failed (task exit 1)')){
                if($statuses -notcontains $status){throw "History omitted status $status"}
            }
            $next=@($grid.Rows | Where-Object { [string]$_.Cells['Status'].Value -eq 'deferred' })[0].Cells['NextJob'].Value
            if($next -ne 'CodexResume-20260101-1200-abcdef03'){throw 'History did not display the follow-up task.'}
            if($grid.SelectedRows.Count -ne 1 -or [string]$grid.SelectedRows[0].Tag -ne 'CodexResume-20260101-1000-abcdef01'){
                throw 'Open selected result must honor the chosen completed run.'
            }
            $completed=@($grid.Rows | Where-Object { [string]$_.Cells['Status'].Value -eq 'completed' })[0]
            $grid.ClearSelection()
            $grid.CurrentCell=$completed.Cells[0]
            $completed.Selected=$true
            if($response.Text -ne 'SCHEDULER_QA_COMPLETED'){throw "Completed run's actual Codex reply was not visible: $($response.Text)"}
            if($transcript.Text -notmatch 'Codex exit code: 0'){throw 'Recorded worker transcript was not visible.'}
            $deferred=@($grid.Rows | Where-Object { [string]$_.Cells['Status'].Value -eq 'deferred' })[0]
            $grid.ClearSelection()
            $grid.CurrentCell=$deferred.Cells[0]
            $deferred.Selected=$true
            if($response.Text -ne 'Usage limit reached'){throw 'Failed-run error was not visible.'}
            $script:historySeen=$true
        } catch {
            $script:historyError=$_.Exception.Message
        } finally {
            if($dialog){$dialog.Close()}
        }
    })
    $timer.Start()
    Show-CodexRunHistoryDialog -Owner $owner -Directory $temp -RecentTasks @($legacyTask) -SelectedName 'CodexResume-20260101-1000-abcdef01'
    if($script:historyError){throw $script:historyError}
    if(-not $script:historySeen){throw 'The history dialog did not render its persisted outcomes.'}
    Write-Host 'WinForms history dialog renders completed, deferred, unreadable and follow-up task PASS.'
} finally {
    $timer.Stop()
    $timer.Dispose()
    $owner.Dispose()
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-NoUnhandledWinFormsErrors
