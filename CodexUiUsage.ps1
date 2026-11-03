# Codex-specific App Server quota reader and update controller.
# Launch the existing CodexUsage.js reader without blocking the Windows Forms
# message loop. The UI polls only for process completion; no persistent service.
function Start-UsageRead {
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    $cliJs = Get-CodexCliJs
    $helper = Join-Path $PSScriptRoot 'CodexUsage.js'
    if (-not (Test-Path -LiteralPath $cliJs -PathType Leaf)) { throw 'Codex npm entrypoint not found. Update/install Codex via npm.' }
    if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'CodexUsage.js is missing. Extract the complete release.' }
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $node
    [void]$start.ArgumentList.Add($helper)
    [void]$start.ArgumentList.Add('--cli-js')
    [void]$start.ArgumentList.Add($cliJs)
    $chosen = Get-DashboardUsageModel
    if ($chosen) { [void]$start.ArgumentList.Add('--model'); [void]$start.ArgumentList.Add($chosen) }
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Could not start Codex usage reader.' }
        $script:ui.Usage.usageRequestedModel = $chosen
        return $process
    } catch {
        $process.Dispose()
        throw
    }
}

function Format-ResetTime {
    param($Seconds)
    if ($null -eq $Seconds) { return 'Reset time unavailable' }
    return 'Resets ' + [DateTimeOffset]::FromUnixTimeSeconds([long]$Seconds).LocalDateTime.ToString('ddd MMM d, h:mm tt')
}

$usagePoll = New-Object System.Windows.Forms.Timer
$usagePoll.Interval = 300

function Render-UsageCard {
    param($Card, $Window, [string]$FallbackTitle)
    if (-not $Window) {
        $Card.Title.Text = $FallbackTitle
        $Card.Remaining.Text = 'Not reported'
        Set-AeroProgress $Card.Bar $null
        $Card.Reset.Text = 'No window supplied by Codex'
        return
    }
    $Card.Title.Text = [string]$Window.label
    if ($null -eq $Window.remainingPercent) {
        $Card.Remaining.Text = 'Unavailable'
        Set-AeroProgress $Card.Bar $null
    } else {
        $remaining = [double]$Window.remainingPercent
        $Card.Remaining.Text = ('{0:0.#}% remaining' -f $remaining)
        Set-AeroProgress $Card.Bar $remaining
    }
    $Card.Reset.Text = Format-ResetTime $Window.resetsAt
}

function Apply-UsageSnapshot {
    param($Snapshot)
    $script:ui.Usage.usageSnapshot = $Snapshot
    $script:ui.Usage.usageSnapshotRequestedModel = $script:ui.Usage.usageRequestedModel
    $script:ui.Usage.usageSnapshotReceivedAt = Get-Date
    $script:ui.Usage.usageReadFailed = $false
    Apply-CodexModelCatalog -Snapshot $Snapshot
    $windows = @($Snapshot.windows | Where-Object { $null -ne $_ })
    Render-UsageCard $usageCards[0] $(if ($windows.Count -ge 1) { $windows[0] } else { $null }) 'Primary window'
    Render-UsageCard $usageCards[1] $(if ($windows.Count -ge 2) { $windows[1] } else { $null }) 'Secondary window'
    $availability = switch ([string]$Snapshot.ordinaryUsageAllowed) {
        'True' { 'Usage allowed' }
        'False' { 'Usage restricted' }
        default { 'Availability not reported' }
    }
    $permission = "Model $($Snapshot.model) | Quota $($Snapshot.bucketId) | $availability"
    if ($Snapshot.limitReachedType) { $permission += "; limit: $($Snapshot.limitReachedType)" }
    # No timestamps or refresh labels in the cards. The state is refreshed
    # automatically; diagnostic details remain available on hover.
    foreach($card in $usageCards) {
        $usageHints.SetToolTip($card.Panel,$permission)
    }
    $useReset.Enabled = $false
    if ($Snapshot.recommendationKind -eq 'exhausted-window' -and $Snapshot.recommendedResetAt) {
        $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$Snapshot.recommendedResetAt).LocalDateTime
        $useReset.Enabled = ($reset.AddMinutes(2) -gt (Get-Date))
    }
    Update-SchedulingEligibility
    Update-DashboardLayout
}

function Set-UsageUnavailable {
    param([string]$Reason)
    $script:ui.Usage.usageReadFailed = $true
    $script:ui.Usage.usageSnapshot = $null
    $script:ui.Usage.usageSnapshotReceivedAt = [datetime]::MinValue
    $script:ui.Usage.usageSnapshotRequestedModel = ''
    foreach ($card in $usageCards) {
        $card.Remaining.Text = 'Unavailable'
        Set-AeroProgress $card.Bar $null
        $card.Reset.Text = 'Usage unavailable; retrying automatically'
        $usageHints.SetToolTip($card.Panel,$Reason)
        $usageHints.SetToolTip($card.Reset,$Reason)
    }
    $useReset.Enabled = $false
    Update-SchedulingEligibility
    Update-DashboardLayout
}

function Request-UsageRefresh {
    if ($script:ui.Usage.usageProcess) {
        $script:ui.Usage.usageRefreshQueued = $true
        Update-SchedulingEligibility
        return
    }
    try {
        $script:ui.Usage.usageProcess = Start-UsageRead
        $script:ui.Usage.usageStarted = Get-Date
        Update-SchedulingEligibility
        $usagePoll.Start()
    } catch {
        Set-UsageUnavailable -Reason $_.Exception.Message
    }
}

$usagePoll.Add_Tick({
    if (-not $script:ui.Usage.usageProcess) { $usagePoll.Stop(); return }
    $process = $script:ui.Usage.usageProcess
    if (-not $process.HasExited -and ((Get-Date) - $script:ui.Usage.usageStarted).TotalSeconds -lt 22) { return }
    $usagePoll.Stop()
    $script:ui.Usage.usageProcess = $null
    try {
        if (-not $process.HasExited) {
            $process.Kill($true)
            throw 'Codex usage query timed out.'
        }
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $lines = @($output -split '[\r\n]+' | Where-Object { $_ })
        if ($lines.Count -eq 0) { throw "No Codex usage response. $errorOutput" }
        $snapshot = $lines[-1] | ConvertFrom-Json -ErrorAction Stop
        if (-not $snapshot.ok) { throw [string]$snapshot.error }
        Apply-UsageSnapshot $snapshot
    } catch {
        Set-UsageUnavailable -Reason $_.Exception.Message
    } finally {
        $process.Dispose()
        if ($script:ui.Usage.usageRefreshQueued) {
            $script:ui.Usage.usageRefreshQueued = $false
            Request-UsageRefresh
        }
    }
})
$useReset.Add_Click({
    if (-not $script:ui.Usage.usageSnapshot -or -not $script:ui.Usage.usageSnapshot.recommendedResetAt) { return }
    $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$script:ui.Usage.usageSnapshot.recommendedResetAt).LocalDateTime
    $after = $reset.AddMinutes(2)
    $rounded = [datetime]::new($after.Year,$after.Month,$after.Day,$after.Hour,$after.Minute,0)
    if ($after -gt $rounded) { $rounded = $rounded.AddMinutes(1) }
    if ($rounded -le (Get-Date)) {
        $useReset.Enabled = $false
        Request-SystemRefresh
        return
    }
    Set-SelectedRunTime $rounded
})
