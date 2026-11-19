# Generate disposable runner files without replacing the application's dependency lock.
# This helper does not restore plugins, compile or launch the app; the two
# application build entrypoints perform the complete Windows capability check.
[CmdletBinding()]
param([string]$FlutterExecutable='')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Invoke-PreviewBuild.ps1')
. (Join-Path $PSScriptRoot 'Test-WindowsBuildPrerequisites.ps1')
if(-not $FlutterExecutable){$FlutterExecutable=(Get-Command flutter.bat -CommandType Application -ErrorAction Stop).Source}
$version=Invoke-ContinuumBuildProcess -FilePath $FlutterExecutable `
    -ArgumentList @('--suppress-analytics','--version','--machine') -WorkingDirectory $project -TimeoutSeconds 120
if($version.ExitCode -ne 0){throw "Flutter runner SDK check failed (exit $($version.ExitCode)): $($version.Stderr.Trim())"}
$metadata=ConvertFrom-ContinuumPrerequisiteJson -Text $version.Stdout -Description 'Flutter runner SDK check' -RootKind Object -RequiredProperty frameworkVersion
[void](Assert-ContinuumFlutterMetadata -Metadata $metadata -FlutterExecutable $FlutterExecutable)
$lockPath=Join-Path $project 'pubspec.lock'
$guardDirectory=Join-Path $project '.dart_tool'
[void][IO.Directory]::CreateDirectory($guardDirectory)
$guardPath=Join-Path $guardDirectory 'continuum-runner.lock'
try{
    $generationLock=[IO.File]::Open($guardPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
}catch{
    throw "Cannot acquire the runner-generation lock in '$project'. Another source build may be generating this runner, or the folder is not writable. Close the other build or correct folder access, then retry."
}
try {
    # Acquire before reading: a second generator must never snapshot another
    # invocation's temporary SDK-only lock and restore it over the reviewed one.
    $lockBytes=[IO.File]::ReadAllBytes($lockPath)
    Push-Location -LiteralPath $project
    try {
        Invoke-ContinuumBuildStep -Name 'Flutter Windows runner generation' -FilePath $FlutterExecutable `
            -ArgumentList @('create','--no-pub','--platforms=windows','--project-name','codex_resume_flutter','.') `
            -WorkingDirectory $project -TimeoutSeconds 240
    } finally {
        try{[IO.File]::WriteAllBytes($lockPath,$lockBytes)}finally{Pop-Location}
    }
    & (Join-Path $PSScriptRoot 'Install-WindowsIcon.ps1')
}finally{
    # Keep the harmless file. OS handle ownership, not its presence, is the
    # lock, so a crash cannot leave a stale marker that blocks future builds.
    $generationLock.Dispose()
}
