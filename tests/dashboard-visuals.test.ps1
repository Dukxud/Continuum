# Render the actual WPF controls: green and blue filled segments, pale tracks,
# and compositor-driven animation while percentages do not change.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinFormsEventGuard.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'legacy/winforms/CodexFlowingBar.ps1')
function Require($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }

function Get-RenderedPixels($progress) {
    $bmp = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        400,18,96,96,[System.Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($progress.Child)
    $bytes = [byte[]]::new(400*18*4)
    $bmp.CopyPixels($bytes,400*4,0)
    return ,$bytes
}
function Get-Pixel($pixels,[int]$x,[int]$y) {
    $offset = ($y * 400 + $x) * 4
    return [pscustomobject]@{ B=[int]$pixels[$offset];G=[int]$pixels[$offset+1];R=[int]$pixels[$offset+2] }
}
$form = [System.Windows.Forms.Form]::new()
$form.ClientSize = [System.Drawing.Size]::new(460,110)
try {
    $quota = New-FlowingProgressBar $form 10 10 400 18 'quota'
    $time = New-FlowingProgressBar $form 10 50 400 18 'time'
    Set-FlowingProgress $quota 60
    Set-FlowingProgress $time 60
    $form.Show()
    for ($i=0;$i -lt 12;$i++){[System.Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 30}
    $q0 = Get-RenderedPixels $quota
    $t0 = Get-RenderedPixels $time
    $qFill = Get-Pixel $q0 48 10
    $tFill = Get-Pixel $t0 48 10
    $qTrack = Get-Pixel $q0 350 10
    $tTrack = Get-Pixel $t0 350 10
    Write-Host ("WPF pixel evidence: usage-fill=R{0}/G{1}/B{2}; usage-track=R{3}/G{4}/B{5}; time-fill=R{6}/G{7}/B{8}; time-track=R{9}/G{10}/B{11}" -f $qFill.R,$qFill.G,$qFill.B,$qTrack.R,$qTrack.G,$qTrack.B,$tFill.R,$tFill.G,$tFill.B,$tTrack.R,$tTrack.G,$tTrack.B)
    $scan=@()
    foreach($x in @(20,45,70,95,120,145,170,195,220)) {
        $p=Get-Pixel $t0 $x 12
        $scan+=("x$x=$($p.R)/$($p.G)/$($p.B)")
    }
    Write-Host ("WPF time-fill sweep y12: " + ($scan -join ', '))
    Require ($qFill.G -gt $qFill.R) 'Usage bar must actually render green.'
    Require ($tFill.B -gt $tFill.R) 'Time bar must actually render blue.'
    Require ($qFill.R -lt $qTrack.R -or $qFill.G -gt $qTrack.G) 'Usage fill must look different from the unfilled track.'
    # A moving glint can temporarily wash out one pixel. Test sustained
    # material contrast at multiple distinct positions, not animation phase.
    $timeContrastSamples=0
    $quotaGreenSamples=0
    foreach($x in @(100,125,150,175,200)) {
        $tSample=Get-Pixel $t0 $x 12
        $qSample=Get-Pixel $q0 $x 12
        if([math]::Abs($tSample.R-$tTrack.R) -gt 25) { $timeContrastSamples++ }
        if($qSample.G -gt $qSample.R -and [math]::Abs($qSample.R-$qTrack.R) -gt 25) { $quotaGreenSamples++ }
    }
    Require ($timeContrastSamples -ge 4) "Time fill must differ from pale track at 4 of 5 positions ($timeContrastSamples)."
    Require ($quotaGreenSamples -ge 4) "Usage fill must be visibly green at 4 of 5 positions ($quotaGreenSamples)."

    for ($i=0;$i -lt 16;$i++){[System.Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 35}
    $q1 = Get-RenderedPixels $quota
    $t1 = Get-RenderedPixels $time
    # Pixel differences across the filled portion prove the shine moves on-screen,
    # rather than merely changing a hidden animation parameter.
    $qChanged = 0; $tChanged = 0
    for ($y=3; $y -lt 15; $y+=3) {
        for ($x=10; $x -lt 200; $x+=5) {
            $index = ($y*400+$x)*4
            if ([math]::Abs([int]$q1[$index+1]-[int]$q0[$index+1]) -gt 6) {$qChanged++}
            if ([math]::Abs([int]$t1[$index]-[int]$t0[$index]) -gt 6) {$tChanged++}
        }
    }
    Require ($qChanged -gt 3) "Usage shine not visibly moving ($qChanged changed pixels)."
    Require ($tChanged -gt 3) "Countdown shine not visibly moving ($tChanged changed pixels)."
    Require ($quota.Child.Value -eq 60 -and $time.Child.Value -eq 60) 'Animation must not alter real progress.'
    Write-Host "WPF compositor renders colored bars and moving shine: usage=$qChanged, time=$tChanged"
} finally { $form.Close();$form.Dispose() }
Assert-NoUnhandledWinFormsErrors
