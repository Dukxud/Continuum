# Local, unsigned engineering preview only. Never publishes or bypasses AV.
[CmdletBinding()]
param(
    [string]$OutputDirectory=(Join-Path $HOME 'Downloads\CodexResumeSchedulerFlutter'),
    [switch]$PackageVerifiedBuild
)
$ErrorActionPreference='Stop'
$project=$PSScriptRoot
$root=Split-Path -Parent $project
if(-not $IsWindows){throw 'The preview package targets Windows.'}
if($PackageVerifiedBuild -and $env:GITHUB_ACTIONS -ne 'true'){
    throw 'Prevalidated-package mode is restricted to the isolated GitHub Actions build.'
}
$flutter=$null
if(-not $PackageVerifiedBuild){
    $flutter=(Get-Command flutter.bat -ErrorAction SilentlyContinue)
    if(-not $flutter){throw 'Flutter SDK not on PATH.'}
}
$label='CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW'
$destination=Join-Path $OutputDirectory $label
$zip=Join-Path $OutputDirectory ($label+'.zip')
if((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $zip)){
    throw "Review package already exists: $destination or $zip"
}
& pwsh -NoProfile -File (Join-Path $root 'tests/flutter-port-source.test.ps1')
if($LASTEXITCODE -ne 0){throw 'Flutter source integrity check failed.'}
if(-not $PackageVerifiedBuild){
Push-Location $project
try{
    & pwsh -NoProfile -STA -File (Join-Path $root 'tests/flutter-port-bridge.test.ps1')
    if($LASTEXITCODE -ne 0){throw 'Live Windows bridge integration failed.'}
    & $flutter.Source create --platforms=windows --project-name codex_resume_flutter .
    if($LASTEXITCODE -ne 0){throw 'Flutter Windows runner creation failed.'}
    & $flutter.Source pub get
    if($LASTEXITCODE -ne 0){throw 'Flutter dependencies failed.'}
    & $flutter.Source analyze --no-fatal-infos
    if($LASTEXITCODE -ne 0){throw 'Dart analyzer found errors; preview was not launched.'}
    & $flutter.Source test
    if($LASTEXITCODE -ne 0){throw 'Flutter tests failed. No preview will be built.'}
    & $flutter.Source build windows --release
    if($LASTEXITCODE -ne 0){throw 'Flutter release build failed.'}
}finally{Pop-Location}
}
$release=Join-Path $project 'build\windows\x64\runner\Release'
$exe=Join-Path $release 'codex_resume_flutter.exe'
if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Flutter executable is missing.'}
foreach($required in @('flutter_windows.dll','data')){
    if(-not (Test-Path -LiteralPath (Join-Path $release $required))){
        throw "Flutter release payload incomplete: $required"
    }
}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
try{
    [void](New-Item -ItemType Directory -Path $destination -Force)
    Copy-Item -Path (Join-Path $release '*') -Destination $destination -Recurse -Force -ErrorAction Stop
    $mustCopy=@('CodexResumeScheduler.ps1','CodexRunEngine.ps1','CodexData.ps1',
        'CodexJobStore.ps1','CodexUsage.js','CodexRunJob.vbs')
    foreach($relative in $mustCopy){
        $from=Join-Path $root $relative
        if(-not (Test-Path -LiteralPath $from -PathType Leaf)){throw "Required worker file missing: $relative"}
        Copy-Item -LiteralPath $from -Destination (Join-Path $destination $relative) -ErrorAction Stop
    }
    $componentNames=@('RuntimeBundle','OneTimeTasks','GitRepository','JobOutcomes','SettingsStore')
    foreach($component in $componentNames){
        $source=Join-Path $root "components/$component"
        $target=Join-Path $destination "components/$component"
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
        Copy-Item -LiteralPath $source -Destination $target -Recurse -ErrorAction Stop
    }
    $bridgeFolder=Join-Path $destination 'flutter_port'
    [void](New-Item -ItemType Directory -Path $bridgeFolder -Force)
    Copy-Item -LiteralPath (Join-Path $project 'windows_bridge.ps1') -Destination $bridgeFolder -ErrorAction Stop
    @'
UNSIGNED FLUTTER ENGINEERING PREVIEW — NOT FOR PUBLIC DISTRIBUTION.
No digital signatures or antivirus exclusions have been applied.
Requires PowerShell 7, Node.js, Git and Codex CLI (npm installation).
This is a Windows frontend using the existing v1.16 worker and Task Scheduler.
Run codex_resume_flutter.exe. A working signed-in desktop is required.
No publisher authentication or full device acceptance is asserted.
'@ | Set-Content -LiteralPath (Join-Path $destination 'UNSIGNED-REVIEW-ONLY.txt') -Encoding utf8
    $files=@(Get-ChildItem -LiteralPath $destination -File -Recurse |
        Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
        Sort-Object FullName)
    $lines=@(foreach($file in $files){
        $relative=$file.FullName.Substring($destination.Length+1).Replace('\','/')
        "$(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 | Select-Object -ExpandProperty Hash)  $relative"
    })
    $lines | Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding utf8
    Compress-Archive -LiteralPath $destination -DestinationPath $zip -CompressionLevel Optimal
    if(-not (Test-Path -LiteralPath $zip -PathType Leaf)){throw 'Preview ZIP was not created.'}
    if((Get-Item -LiteralPath $zip).Length -lt 1048576){throw 'Unexpectedly small Windows review package.'}
    Write-Host "Unsigned Windows Flutter review package: $zip" -ForegroundColor Green
    Write-Host "Standalone executable: $(Join-Path $destination 'codex_resume_flutter.exe')"
}catch{
    if(Test-Path -LiteralPath $destination){Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue}
    throw
}
