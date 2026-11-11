# Confirm the generated Flutter runner and compiled EXE use the same pinned app icon.
# No Codex session is started and no Windows Task Scheduler state is changed.
[CmdletBinding()]
param([string]$ExecutablePath='')
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows icon resource validation requires Windows.'}
$project=Join-Path (Split-Path -Parent $PSScriptRoot) 'src/desktop'
& pwsh -NoProfile -File (Join-Path $project 'scripts/Install-WindowsIcon.ps1') -VerifyOnly
if($LASTEXITCODE -ne 0){throw 'Pinned runner resource verification failed.'}
if(-not $ExecutablePath){return}
if(-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)){throw 'Compiled Flutter executable is missing.'}
Add-Type -AssemblyName System.Drawing
$expected=[Drawing.Icon]::new((Join-Path $project 'branding/continuum.ico'),[Drawing.Size]::new(32,32))
$actual=[Drawing.Icon]::ExtractAssociatedIcon([IO.Path]::GetFullPath($ExecutablePath))
if($null -eq $actual){throw 'Windows executable has no associated application icon.'}
try{
    $e=$expected.ToBitmap();$a=$actual.ToBitmap()
    try{
        $points=@(@(5,5),@(16,16),@(22,16))
        foreach($point in $points){
            $x=[int]$point[0];$y=[int]$point[1]
            $left=$e.GetPixel($x,$y);$right=$a.GetPixel($x,$y)
            if([Math]::Abs([int]$left.R-[int]$right.R) -gt 45 -or
                [Math]::Abs([int]$left.G-[int]$right.G) -gt 45 -or
                [Math]::Abs([int]$left.B-[int]$right.B) -gt 45){
                throw "Executable icon does not match Continuum at pixel ($x,$y)."
            }
        }
    }finally{$e.Dispose();$a.Dispose()}
}finally{$expected.Dispose();$actual.Dispose()}
Write-Host 'Compiled Windows executable embeds Continuum identity icon PASS.' -ForegroundColor Green
