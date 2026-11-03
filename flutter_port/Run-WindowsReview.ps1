# Bounded Flutter Windows review; no CI, no releases, no task mutations.
[CmdletBinding()]
param([switch]$TestsOnly)
$ErrorActionPreference='Stop'
$project=$PSScriptRoot
$root=Split-Path -Parent $project
if(-not (Test-Path -LiteralPath (Join-Path $root 'CodexRunEngine.ps1'))){throw 'Run from the complete Scheduler checkout.'}
$flutter=Get-Command flutter.bat -ErrorAction SilentlyContinue
if(-not $flutter){$flutter=Get-Command flutter -ErrorAction SilentlyContinue}
if(-not $flutter){
    throw 'Flutter SDK missing. Install stable Flutter from https://docs.flutter.dev/install, add its bin directory to PATH, and install Visual Studio Desktop development with C++.'
}
Push-Location $project
try{
    $env:CODEX_SCHEDULER_SOURCE=$root
    & $flutter.Source create --platforms=windows --project-name codex_resume_flutter .
    if($LASTEXITCODE -ne 0){throw 'Flutter Windows runner generation failed.'}
    & $flutter.Source pub get
    if($LASTEXITCODE -ne 0){throw 'Flutter dependencies failed.'}
    & $flutter.Source test
    if($LASTEXITCODE -ne 0){throw 'Flutter test failed; preview was not started.'}
    if($TestsOnly){Write-Host 'Flutter tests passed; review launch skipped.' -ForegroundColor Green;return}
    & $flutter.Source run -d windows
    if($LASTEXITCODE -ne 0){throw 'Flutter Windows build or launch failed. Run flutter doctor -v to diagnose toolchain requirements.'}
}finally{
    Pop-Location
}
