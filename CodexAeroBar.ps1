# Scheduler adapter around the standalone AeroProgress component.
# Only this file knows Codex settings, WPF fallback and quota/countdown roles.
Import-Module (Join-Path $PSScriptRoot 'components/AeroProgress/AeroProgress.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'components/ProgressHost/ProgressHost.psm1') -Force -ErrorAction Stop
$script:aeroChecked = $false
$script:aeroAvailable = $false
$script:aeroError = ''
$script:aeroBars = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
$script:nativeBars = [System.Collections.Generic.List[object]]::new()

function Initialize-AeroAppearance {
    param($Settings)
    $defaults = [ordered]@{
        quota = 'green'
        weekly = 'cyan'
        time = 'blue'
        working = 'amber'
        finish = 0
        lighting = 0
        shimmer = 100
        speed = 100
        aero = $true
    }
    $stored = if ($Settings) { $Settings.barAppearance } else { $null }
    if ($stored) {
        foreach ($name in @($defaults.Keys)) {
            if ($stored.PSObject.Properties[$name]) {
                $defaults[$name] = $stored.$name
            }
        }
    }
    foreach ($kind in @('quota','weekly','time','working')) {
        if ($defaults[$kind] -notin @('green','blue','cyan','violet','amber','red') -and
            [string]$defaults[$kind] -notmatch '^#[0-9a-fA-F]{6}$') {
            $defaults[$kind] = switch ($kind) { quota {'green'} weekly {'cyan'} time {'blue'} working {'amber'} }
        }
        if ([string]$defaults[$kind] -match '^#[0-9a-fA-F]{6}$') {
            $defaults[$kind] = ([string]$defaults[$kind]).ToUpperInvariant()
        }
    }
    foreach ($key in @('finish','lighting')) {
        if ($defaults[$key] -notin @(0,1,2)) { $defaults[$key] = 0 }
        $defaults[$key] = [int]$defaults[$key]
    }
    foreach ($key in @('shimmer','speed')) {
        try { $defaults[$key] = [int]$defaults[$key] } catch { $defaults[$key] = 100 }
    }
    $defaults['shimmer'] = [math]::Clamp($defaults['shimmer'],0,200)
    $defaults['speed'] = [math]::Clamp($defaults['speed'],25,300)
    $defaults['aero'] = ($defaults['aero'] -eq $true)
    $script:aeroAppearance = $defaults
}
Initialize-AeroAppearance $null

function Update-AeroAppearance {
    param([System.Collections.IDictionary]$Appearance)
    # Older callers only supplied quota/time; preserve the other independent
    # roles instead of silently clearing their colors on a live update.
    $merged=[ordered]@{}
    foreach($key in $script:aeroAppearance.Keys){$merged[$key]=$script:aeroAppearance[$key]}
    foreach($key in $Appearance.Keys){$merged[$key]=$Appearance[$key]}
    $script:aeroAppearance=$merged
    $Appearance=$merged
    # Direct WPF bars exist when the browser runtime is unavailable or disabled.
    # They own stable ElementHost controls, and must receive live theme edits too.
    foreach ($entry in @($script:nativeBars)) {
        if ($entry.Bar.IsDisposed) {
            [void]$script:nativeBars.Remove($entry)
            continue
        }
        $role=if($entry.Bar.Tag -and $entry.Bar.Tag.Working){'working'}else{$entry.Kind}
        Set-FlowingProgressColors -Bar $entry.Bar -Kind $role -Color ([string]$Appearance[$role])
    }
    foreach ($bar in @($script:aeroBars)) {
        if ($bar.IsDisposed) {
            [void]$script:aeroBars.Remove($bar)
            continue
        }
        $role=if($bar.Tag.Working){'working'}else{[string]$bar.Tag.Kind}
        $bar.Tag.Color = [string]$Appearance[$role]
        if ((Get-ProgressHostSurface -Primary $bar) -ne $bar) {
            Reset-ProgressHostFallback -Primary $bar
            Ensure-AeroFallback $bar
        } else { Send-AeroState $bar }
    }
}


function Test-AeroRenderer {
    if ($env:CODEX_BAR_RENDERER -eq 'wpf') {
        $script:aeroError = 'WPF fallback explicitly selected.'
        return $false
    }
    if ($script:aeroChecked -and $script:aeroAvailable) { return $true }
    $script:aeroChecked = $true
    $script:aeroSdk = Join-Path $PSScriptRoot 'AeroWebView2'
    $script:aeroAsset = Join-Path $PSScriptRoot 'assets/AeroBar.html'
    $support = Test-AeroProgressSupport -SdkDirectory $script:aeroSdk -AssetPath $script:aeroAsset
    $script:aeroAvailable = [bool]$support.Available
    $script:aeroError = [string]$support.Reason
    return $script:aeroAvailable
}

# Codex owns this metadata and can also inject a host-specific failure.
# The renderer module independently reports asynchronous WebView2 failures.
function Get-CodexAeroFailure {
    param([System.Windows.Forms.Control]$Bar)
    if ($Bar.Tag -and $Bar.Tag.Failure) { return [string]$Bar.Tag.Failure }
    return [string](Get-AeroProgressViewStatus -View $Bar).Failure
}

function Send-AeroState {
    param([System.Windows.Forms.Control]$Bar)
    if (-not $Bar -or $Bar.IsDisposed -or (Get-ProgressHostSurface -Primary $Bar) -ne $Bar) { return }
    if (Get-CodexAeroFailure -Bar $Bar) { return }
    # The module queues this state if WebView2 has not finished starting.
    Set-AeroProgressViewState -View $Bar -State @{
        type='set'
        value=if ($Bar.Tag.Working) { 1.0 } elseif ($null -eq $Bar.Tag.Percent) { 0.0 } else { [double]$Bar.Tag.Percent / 100.0 }
        mode=if($Bar.Tag.Working){'working'}else{'progress'}
        color=[string]$Bar.Tag.Color
        finish=[int]$script:aeroAppearance['finish']
        lighting=[int]$script:aeroAppearance['lighting']
        shimmer=[double]$script:aeroAppearance['shimmer']/100.0
        speed=[double]$script:aeroAppearance['speed']/100.0
        aero=[bool]$script:aeroAppearance['aero']
    }
}

# A failed renderer must not leave a permanent blank bar. The view itself
# stays as the stable caller reference; its fallback is a WPF ElementHost.
function Ensure-AeroFallback {
    param([System.Windows.Forms.Control]$Bar)
    if (-not $Bar -or $Bar.IsDisposed -or (Get-ProgressHostSurface -Primary $Bar) -ne $Bar) { return }
    $failure = Get-CodexAeroFailure -Bar $Bar
    if (-not $failure) { return }
    $kind=[string]$Bar.Tag.Kind
    $role=if($Bar.Tag.Working){'working'}else{$kind}
    $color=if($Bar.Tag.Color){[string]$Bar.Tag.Color}else{[string]$script:aeroAppearance[$role]}
    $factory={
        param($parent,$bounds)
        return New-FlowingProgressBar $parent $bounds.X $bounds.Y $bounds.Width $bounds.Height $kind -Color $color
    }.GetNewClosure()
    try {
        $replacement=Repair-ProgressHost -Primary $Bar -Failed $true -FallbackFactory $factory
        if($replacement){
            if($Bar.Tag.Working){
                $replacement.AccessibleName='Codex working; completion unknown'
                Set-FlowingProgress $replacement 100
                $replacement.Child.IsIndeterminate=$true
            }else{Set-FlowingProgress $replacement $Bar.Tag.Percent}
        }
    } catch {
        $script:aeroError = "Aero recovery failed: $($_.Exception.Message)"
    }
}
function Get-AeroProgressSurface {
    param([System.Windows.Forms.Control]$Bar)
    return Get-ProgressHostSurface -Primary $Bar
}
function Remove-AeroProgressBar {
    param([System.Windows.Forms.Control]$Bar)
    if(-not $Bar){return}
    foreach ($entry in @($script:nativeBars)) {
        if ([object]::ReferenceEquals($entry.Bar,$Bar)) {
            [void]$script:nativeBars.Remove($entry)
        }
    }
    [void]$script:aeroBars.Remove($Bar)
    Remove-ProgressHost -Primary $Bar
}

function Start-AeroHealthMonitor {
    if (-not $script:aeroHealthTimer) {
        $script:aeroHealthTimer = [System.Windows.Forms.Timer]::new()
        $script:aeroHealthTimer.Interval = 900
        $script:aeroHealthTimer.Add_Tick({
            foreach ($bar in @($script:aeroBars)) {
                if ($bar.IsDisposed) {
                    [void]$script:aeroBars.Remove($bar)
                    continue
                }
                Ensure-AeroFallback $bar
            }
            if ($script:aeroBars.Count -eq 0) { $script:aeroHealthTimer.Stop() }
        })
    }
    if (-not $script:aeroHealthTimer.Enabled) { $script:aeroHealthTimer.Start() }
}

# Both rendering paths return stable controls with explicit host ownership.
function New-CodexNativeProgressBar {
    param(
        [System.Windows.Forms.Control]$Parent,
        [int]$X,[int]$Y,[int]$Width,[int]$Height,
        [ValidateSet('quota','weekly','time','working')][string]$Kind,
        [string]$Color
    )
    $bar = New-FlowingProgressBar $Parent $X $Y $Width $Height $Kind -Color $Color
    $bar.Tag=[pscustomobject]@{Kind=$Kind;Percent=$null;Working=$false;Color=$Color}
    $script:nativeBars.Add([pscustomobject]@{ Bar=$bar; Kind=$Kind })
    return $bar
}

function New-AeroProgressBar {
    param(
        [System.Windows.Forms.Control]$Parent,
        [int]$X,[int]$Y,[int]$Width,[int]$Height,
        [ValidateSet('quota','weekly','time','working')][string]$Kind,
        [string]$Color='',
        [string]$UserDataDirectory=''
    )
    $chosen = if ($Color -and (Test-AeroProgressColor $Color)) {
        $Color
    } else { [string]$script:aeroAppearance[$Kind] }
    if (-not (Test-AeroRenderer)) {
        return New-CodexNativeProgressBar $Parent $X $Y $Width $Height $Kind $chosen
    }
    try {
        $view = New-AeroProgressView -Parent $Parent -X $X -Y $Y -Width $Width -Height $Height `
            -Color $chosen -AccessibleName $(switch($Kind){quota{'Five-hour usage remaining'}weekly{'Weekly usage remaining'}working{'Codex working; completion unknown'}default{'Time until scheduled run'}}) `
            -SdkDirectory $script:aeroSdk -AssetPath $script:aeroAsset `
            -UserDataDirectory $(if ($UserDataDirectory) { [IO.Path]::GetFullPath($UserDataDirectory) } else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexResumeScheduler/AeroWebView2' })
        # This Tag belongs only to the Codex adapter; AeroProgress never reads
        # or overwrites it, so independent applications may use their own Tag.
        $view.Tag = [pscustomobject]@{
            Kind = $Kind; Percent = $null; Working = $false; Color = $chosen; Failure = $null
        }
        $script:aeroBars.Add($view)
        Start-AeroHealthMonitor
        Send-AeroState $view
        return $view
    } catch {
        $script:aeroError = "Aero view failed: $($_.Exception.Message)"
        return New-CodexNativeProgressBar $Parent $X $Y $Width $Height $Kind $chosen
    }
}

# Set an actual known countdown/usage percentage. Leaving Working resets
# the appearance role and never animates a fabricated execution percentage.
function Set-AeroProgress {
    param([System.Windows.Forms.Control]$Bar,$Percent)
    if(-not $Bar -or $Bar.IsDisposed){return}
    $value=if($null -eq $Percent){$null}else{[double][math]::Clamp([double]$Percent,0,100)}
    if($Bar -is [System.Windows.Forms.Integration.ElementHost]){
        if($Bar.Tag.Working){
            $Bar.Tag.Working=$false
            $Bar.AccessibleName=switch($Bar.Tag.Kind){quota{'Five-hour usage remaining'}weekly{'Weekly usage remaining'}time{'Time until scheduled run'}default{'Usage remaining'}}
            $Bar.Child.IsIndeterminate=$false
            Set-FlowingProgressColors -Bar $Bar -Kind $Bar.Tag.Kind -Color ([string]$script:aeroAppearance[$Bar.Tag.Kind])
        }
        $Bar.Tag.Percent=$value
        Set-FlowingProgress $Bar $value
        return
    }
    if(-not $Bar.Tag.Working -and $Bar.Tag.Percent -eq $value){return}
    $Bar.Tag.Working=$false
    $Bar.Tag.Percent=$value
    $Bar.Tag.Color=[string]$script:aeroAppearance[$Bar.Tag.Kind]
    $Bar.AccessibleName=switch($Bar.Tag.Kind){quota{'Five-hour usage remaining'}weekly{'Weekly usage remaining'}time{'Time until scheduled run'}default{'Usage remaining'}}
    $active=Get-ProgressHostSurface -Primary $Bar
    if($active -ne $Bar){
        Set-FlowingProgressColors -Bar $active -Kind $Bar.Tag.Kind -Color $Bar.Tag.Color
        $active.AccessibleName=$Bar.AccessibleName
        $active.Child.IsIndeterminate=$false
        Set-FlowingProgress $active $value
        return
    }
    Ensure-AeroFallback $Bar
    $active=Get-ProgressHostSurface -Primary $Bar
    if($active -ne $Bar){Set-FlowingProgress $active $value;return}
    Send-AeroState $Bar
}
# Work has no numerical progress. The optical tube stays full-sized while
# animated currents move inside it; WPF fallback uses its perpetual glint.
function Set-AeroWorking {
    param([System.Windows.Forms.Control]$Bar)
    if(-not $Bar -or $Bar.IsDisposed -or $Bar.Tag.Working){return}
    $Bar.Tag.Working=$true
    $Bar.Tag.Percent=$null
    $Bar.Tag.Color=[string]$script:aeroAppearance['working']
    $Bar.AccessibleName='Codex working; completion unknown'
    if($Bar -is [System.Windows.Forms.Integration.ElementHost]){
        Set-FlowingProgressColors -Bar $Bar -Kind 'working' -Color $Bar.Tag.Color
        Set-FlowingProgress $Bar 100
        $Bar.Child.IsIndeterminate=$true
        return
    }
    $active=Get-ProgressHostSurface -Primary $Bar
    if($active -ne $Bar){
        Set-FlowingProgressColors -Bar $active -Kind 'working' -Color $Bar.Tag.Color
        $active.AccessibleName='Codex working; completion unknown'
        Set-FlowingProgress $active 100
        $active.Child.IsIndeterminate=$true
        return
    }
    Ensure-AeroFallback $Bar
    $active=Get-ProgressHostSurface -Primary $Bar
    if($active -ne $Bar){return} # Ensure-AeroFallback applied the new state
    Send-AeroState $Bar
}
