Initialize-Dashboard
Set-PixelSurfaceStyle -Panel $script:ui.Dashboard.compactRunPanel -Fill '#E7EEFC' -Accent '#547FD2'
Set-PixelAction -Button $script:ui.Dashboard.appearanceButton -Accent '#516F98'
# The countdown timer is created by Initialize-Dashboard; attach the scheduling
# default updater only after that owner initializes it.
$script:ui.Dashboard.countdownTimer.Add_Tick({ Refresh-SuggestedRunTime })

# One timer: active Windows task status every two seconds, all application
# data every minute. GUI-thread work only dispatches asynchronous readers.
$systemRefreshTimer = New-Object System.Windows.Forms.Timer
$systemRefreshTimer.Interval = 2000
$systemRefreshTimer.Add_Tick({
    $scope=if(((Get-Date)-$script:ui.Async.lastFullRefresh).TotalSeconds -ge 60){'Full'}else{'TaskStatus'}
    try {
        Request-SystemRefresh -Scope $scope
        Update-SchedulingEligibility
    }
    catch { Update-Status "System refresh failed: $($_.Exception.Message)" -Alert }
})
$form.Add_Activated({
    # After focus returns from another app or Windows sleep, refresh stale
    # system data immediately without flooding Codex during rapid focus changes.
    if($script:ui.Preferences.settingsReady -and
        ((Get-Date)-$script:ui.Async.lastFullRefresh).TotalSeconds -ge 15) {
        try { Request-SystemRefresh }
        catch { Update-Status "System refresh failed: $($_.Exception.Message)" -Alert }
    }
})
$form.Add_Shown({
    [void][CodexScheduler.NativeWindow]::ShowWindow($form.Handle, 5) # SW_SHOW
    $form.Activate()
    $script:ui.Preferences.settingsReady = $true
    Update-DashboardLayout
    $script:ui.Dashboard.countdownTimer.Start()
    try { Request-SystemRefresh } catch { Update-Status "Startup warning: $($_.Exception.Message)" -Alert }
    $systemRefreshTimer.Start()
    $dataPoll.Start()
})
$form.Add_FormClosing({
    $script:ui.Preferences.settingsTimer.Stop()
    try { Save-CurrentFormState } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not save preferences: $($_.Exception.Message)", 'Settings save error') | Out-Null
    }
})
$form.Add_FormClosed({
    $script:ui.Dashboard.countdownTimer.Stop()
    $systemRefreshTimer.Stop()
    $usagePoll.Stop()
    $dataPoll.Stop()
    foreach ($job in @($script:ui.Async.dataJobs.Values)) {
        try { Stop-Job -Job $job -ErrorAction SilentlyContinue; Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { }
    }
    if ($script:aeroHealthTimer) { $script:aeroHealthTimer.Stop(); $script:aeroHealthTimer.Dispose() }
    if ($script:ui.Usage.usageProcess) {
        try { if (-not $script:ui.Usage.usageProcess.HasExited) { $script:ui.Usage.usageProcess.Kill($true) } } catch { }
        $script:ui.Usage.usageProcess.Dispose()
        $script:ui.Usage.usageProcess = $null
    }
})
[void]$form.ShowDialog()
$systemRefreshTimer.Dispose()
$script:ui.Dashboard.countdownTimer.Dispose()
$script:ui.Preferences.settingsTimer.Dispose()
$usagePoll.Dispose()
$dataPoll.Dispose()
$repoHints.Dispose()
$usageHints.Dispose()
$actionHints.Dispose()
$form.Dispose()
