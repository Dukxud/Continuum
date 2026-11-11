# Generate disposable runner files without replacing the application's dependency lock.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$flutter=Get-Command flutter.bat -ErrorAction Stop
$lockPath=Join-Path $project 'pubspec.lock'
$lockBytes=[IO.File]::ReadAllBytes($lockPath)
Push-Location $project
try {
    # Flutter seeds an SDK-only lock on a fresh project, even with --no-pub.
    # Retain the reviewed application lock for the subsequent enforced restore.
    & $flutter.Source create --no-pub --platforms=windows --project-name codex_resume_flutter .
    if($LASTEXITCODE -ne 0){throw 'Flutter Windows runner generation failed.'}
} finally {
    [IO.File]::WriteAllBytes($lockPath,$lockBytes)
    Pop-Location
}
& (Join-Path $PSScriptRoot 'Install-WindowsIcon.ps1')
