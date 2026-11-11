# Bounded Flutter Windows review; no CI, no releases, no task mutations.
[CmdletBinding()]
param([switch]$TestsOnly)
$ErrorActionPreference='Stop'
$project=$PSScriptRoot
$root=[IO.Path]::GetFullPath((Join-Path $project '../..'))
# Catch a broken bridge before creating or launching a Flutter runner.
& pwsh -NoProfile -File (Join-Path $root 'tests/flutter-port-source.test.ps1')
if($LASTEXITCODE -ne 0){throw 'Flutter bridge source checks failed.'}
if(-not (Test-Path -LiteralPath (Join-Path $root 'src/backend/CodexRunEngine.ps1'))){throw 'Run from the complete Scheduler checkout.'}
$flutter=Get-Command flutter.bat -ErrorAction SilentlyContinue
if(-not $flutter){$flutter=Get-Command flutter -ErrorAction SilentlyContinue}
if(-not $flutter){
    throw 'Flutter SDK missing. Install stable Flutter from https://docs.flutter.dev/install, add its bin directory to PATH, and install Visual Studio Desktop development with C++.'
}
Push-Location $project
$originalSource=$env:CODEX_SCHEDULER_SOURCE
try{
    $env:CODEX_SCHEDULER_SOURCE=$root
    & pwsh -NoProfile -STA -File (Join-Path $root 'tests/flutter-port-bridge.test.ps1')
    if($LASTEXITCODE -ne 0){throw 'Live Windows bridge integration failed.'}
    & $flutter.Source create --no-pub --platforms=windows --project-name codex_resume_flutter .
    if($LASTEXITCODE -ne 0){throw 'Flutter Windows runner generation failed.'}
    & pwsh -NoProfile -File (Join-Path $project 'scripts/Install-WindowsIcon.ps1')
    if($LASTEXITCODE -ne 0){throw 'Continuum native icon installation failed.'}
    & $flutter.Source pub get --enforce-lockfile
    if($LASTEXITCODE -ne 0){throw 'Flutter dependencies failed.'}
    & $flutter.Source analyze --no-pub
    if($LASTEXITCODE -ne 0){throw 'Dart analyzer found errors; preview was not launched.'}
    & $flutter.Source test --no-pub --exclude-tags visual-capture
    if($LASTEXITCODE -ne 0){throw 'Flutter test failed; preview was not started.'}
    if($TestsOnly){Write-Host 'Flutter tests passed; review launch skipped.' -ForegroundColor Green;return}
    & $flutter.Source run -d windows
    if($LASTEXITCODE -ne 0){throw 'Flutter Windows build or launch failed. Run flutter doctor -v to diagnose toolchain requirements.'}
}finally{
    $env:CODEX_SCHEDULER_SOURCE=$originalSource
    Pop-Location
}
