# Bounded Flutter Windows review; no CI, no releases, no task mutations.
[CmdletBinding()]
param([switch]$TestsOnly)
$ErrorActionPreference='Stop'
$project=$PSScriptRoot
$root=[IO.Path]::GetFullPath((Join-Path $project '../..'))
if(-not (Test-Path -LiteralPath (Join-Path $root 'src/backend/CodexRunEngine.ps1'))){throw 'Run from the complete Scheduler checkout.'}
. (Join-Path $project 'scripts/Invoke-PreviewBuild.ps1')
. (Join-Path $project 'scripts/Test-WindowsBuildPrerequisites.ps1')
$tools=Assert-ContinuumWindowsBuildPrerequisites -ProjectDirectory $project
Push-Location -LiteralPath $project
$originalSource=$env:CODEX_SCHEDULER_SOURCE
try{
    $env:CODEX_SCHEDULER_SOURCE=$root
    Invoke-ContinuumPreviewBuild -ProjectDirectory $project -Tools $tools
    if($TestsOnly){Write-Host 'Flutter tests passed; review launch skipped.' -ForegroundColor Green;return}
    & $tools.FlutterExecutable run -d windows --no-pub
    if($LASTEXITCODE -ne 0){throw "Flutter Windows debug build/launch failed (exit $LASTEXITCODE). Review the tool's error above."}
}finally{
    $env:CODEX_SCHEDULER_SOURCE=$originalSource
    Pop-Location
}
