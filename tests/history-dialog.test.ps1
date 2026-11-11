# Exercise actual result-history dialog through the WinForms message loop.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WinFormsEventGuard.ps1')
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/backend/CodexJobStore.ps1')
. (Join-Path $root 'legacy/winforms/CodexUiHistory.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('history-dialog-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -Path $temp -ItemType Directory -Force)
$owner=[System.Windows.Forms.Form]::new()
$timer=[System.Windows.Forms.Timer]::new()
$timer.Interval=120
$script:historySeen=$false
$script:historyError=''
$script:historyStart=Get-Date
$script:capturedCopies=[Collections.Generic.List[string]]::new()
# Intercept the clipboard boundary so tests never replace the user's clipboard.
function Copy-CodexEvidenceText {
    param([string]$Text)
    [void]$script:capturedCopies.Add($Text)
}
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
    $matchingTask=[pscustomobject]@{
        Name='CodexResume-20260101-1000-abcdef01';When=(Get-Date).AddMinutes(-10)
        Status='Completed';Repo='C:\source\BP105-Scheduler-QA'
        Description='gpt-6.1-sol / low | read-only';Session='01a19dcb-aa2d-7632-b490-a5ae1b19e37e'
    }
    $owner.Show()
    $timer.Add_Tick({
        $dialog=$null
        try {
            $dialog=@([System.Windows.Forms.Application]::OpenForms | Where-Object { $_.Text -like 'Recent Codex runs*' }) | Select-Object -First 1
            if(-not $dialog) {
                if((Get-Date)-gt $script:historyStart.AddSeconds(12)){$script:historyError='History dialog did not open.'}
                return
            }
            $split=@($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.SplitContainer] }) | Select-Object -First 1
            if(-not $split){throw 'History must contain both result list and evidence pane.'}
            $actions=@($split.Panel1.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] }) | Select-Object -First 1
            $remove=@($actions.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq 'Remove from history' }) | Select-Object -First 1
            if(-not $remove){throw 'History does not offer removal from the list.'}
            $copyResponse=@($actions.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq 'Copy response' }) | Select-Object -First 1
            $copyLog=@($actions.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq 'Copy worker log' }) | Select-Object -First 1
            if(-not $copyResponse -or -not $copyLog){throw 'Both history copy actions must be present.'}
            foreach($button in @($remove,$copyResponse,$copyLog)){
                if($button.Top -lt 0 -or $button.Bottom -gt $actions.Height){throw 'History action is clipped.'}
            }
            if($copyResponse.Left -lt $remove.Right+8 -or $copyLog.Left -lt $copyResponse.Right+8){throw 'History action buttons overlap.'}
            $grid=@($split.Panel1.Controls | Where-Object { $_ -is [System.Windows.Forms.DataGridView] }) | Select-Object -First 1
            $tabs=@($split.Panel2.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] }) | Select-Object -First 1
            if(-not $tabs -or $tabs.TabPages.Count -ne 2){throw 'Codex response and worker-log tabs are missing.'}
            $response=@($tabs.TabPages[0].Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] }) | Select-Object -First 1
            $transcript=@($tabs.TabPages[1].Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] }) | Select-Object -First 1
            if(-not $response.ReadOnly -or -not $transcript.ReadOnly){throw 'Evidence must be read-only.'}
            if(-not $grid -or $grid.Rows.Count -ne 4){throw 'History must render persisted outcomes and old Windows task records.'}
            # Verified outcome fields must never inherit project/model/session
            # data from the Windows task record.
            $completeRow=@($grid.Rows | Where-Object { [string]$_.Cells['Status'].Value -eq 'completed' })[0]
            if([string]$completeRow.Cells['ExitCode'].Value -cne '0' -or
               [string]$completeRow.Cells['Attempt'].Value -cne '0' -or
               [string]$completeRow.Cells['NextJob'].Value -cne '' -or
               [string]$completeRow.Cells['Message'].Value -cne 'Complete.'){
                throw 'History columns do not match the saved worker outcome.'
            }
            if([string]$completeRow.Cells['When'].Value -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'){
                throw 'History time is formatted for the wrong table.'
            }
            $legacyRow=@($grid.Rows | Where-Object { [string]$_.Cells['Status'].Value -like 'Failed (task*' })[0]
            if([string]$legacyRow.Cells['ExitCode'].Value -cne '' -or
               [string]$legacyRow.Cells['Attempt'].Value -cne '' -or
               [string]$legacyRow.Cells['NextJob'].Value -cne ''){
                throw 'Unverified legacy task metadata was displayed as verified outcome data.'
            }
            $statuses=@($grid.Rows | ForEach-Object { [string]$_.Cells['Status'].Value })
            foreach($status in @('completed','deferred','unreadable','Failed (task exit 1)')){
                if($statuses -notcontains $status){throw "History omitted status $status"}
            }
            $deferredRow=@($grid.Rows | Where-Object { [string]$_.Cells['Status'].Value -eq 'deferred' })[0]
            if([string]$deferredRow.Cells['ExitCode'].Value -cne '17' -or
               [string]$deferredRow.Cells['Attempt'].Value -cne '1' -or
               [string]$deferredRow.Cells['Message'].Value -cne 'Rescheduled.'){
                throw 'Deferred result details were shifted into the wrong columns.'
            }
            $next=$deferredRow.Cells['NextJob'].Value
            if($next -ne 'CodexResume-20260101-1200-abcdef03'){throw 'History did not display the follow-up task.'}
            if($grid.SelectedRows.Count -ne 1 -or [string]$grid.SelectedRows[0].Tag -ne 'CodexResume-20260101-1000-abcdef01'){
                throw 'Open selected result must honor the chosen completed run.'
            }
            if(-not $remove.Enabled){throw 'A selected completed run must enable removal from history.'}
            $completed=@($grid.Rows | Where-Object { [string]$_.Cells['Status'].Value -eq 'completed' })[0]
            $grid.ClearSelection()
            $grid.CurrentCell=$completed.Cells[0]
            $completed.Selected=$true
            if($response.Text -ne 'SCHEDULER_QA_COMPLETED'){throw "Completed run's actual Codex reply was not visible: $($response.Text)"}
            if($transcript.Text -notmatch 'Codex exit code: 0'){throw 'Recorded worker transcript was not visible.'}
            if(-not $copyResponse.Enabled -or -not $copyLog.Enabled){throw 'Evidence copy actions must be enabled for a selected result.'}
            $copyResponse.PerformClick()
            $copyLog.PerformClick()
            if($script:capturedCopies.Count -ne 2 -or $script:capturedCopies[0] -cne 'SCHEDULER_QA_COMPLETED' -or
               $script:capturedCopies[1] -notmatch 'Codex exit code: 0'){throw 'Copy actions did not capture exact response and worker log.'}
            $deferred=@($grid.Rows | Where-Object { [string]$_.Cells['Status'].Value -eq 'deferred' })[0]
            $grid.ClearSelection()
            $grid.CurrentCell=$deferred.Cells[0]
            $deferred.Selected=$true
            if($response.Text -ne 'Usage limit reached'){throw 'Failed-run error was not visible.'}
            $copyResponse.PerformClick()
            if($script:capturedCopies.Count -ne 3 -or $script:capturedCopies[2] -cne 'Usage limit reached'){throw 'Copy response retained stale evidence after selection changed.'}
            $script:historySeen=$true
        } catch {
            $script:historyError=$_.Exception.Message
        } finally {
            if($dialog){$dialog.Close()}
        }
    })
    $timer.Start()
    Show-CodexRunHistoryDialog -Owner $owner -Directory $temp -RecentTasks @($legacyTask,$matchingTask) -SelectedName 'CodexResume-20260101-1000-abcdef01'
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
