# Local, unsigned engineering preview only. Never publishes or bypasses AV.
[CmdletBinding()]
param(
    [string]$OutputDirectory=(Join-Path $HOME 'Downloads\Continuum-Preview'),
    [switch]$PackageVerifiedBuild
)
$ErrorActionPreference='Stop'
$project=$PSScriptRoot
$root=[IO.Path]::GetFullPath((Join-Path $project '../..'))
if(-not $IsWindows){throw 'The preview package targets Windows.'}
if($PackageVerifiedBuild -and $env:GITHUB_ACTIONS -ne 'true'){
    throw 'Prevalidated-package mode is restricted to the isolated GitHub Actions build.'
}
$flutter=$null
if(-not $PackageVerifiedBuild){
    $flutter=(Get-Command flutter.bat -ErrorAction SilentlyContinue)
    if(-not $flutter){throw 'Flutter SDK not on PATH.'}
}
. (Join-Path $project 'scripts/Get-PreviewMetadata.ps1')
$preview=Get-ContinuumPreviewMetadata -PubspecPath (Join-Path $project 'pubspec.yaml')
$label=$preview.PackageName
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
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
    & pwsh -NoProfile -File (Join-Path $project 'scripts/Initialize-WindowsRunner.ps1')
    if($LASTEXITCODE -ne 0){throw 'Windows runner initialization failed.'}
    & $flutter.Source pub get --enforce-lockfile
    if($LASTEXITCODE -ne 0){throw 'Flutter dependencies failed.'}
    & $flutter.Source analyze --no-pub
    if($LASTEXITCODE -ne 0){throw 'Dart analyzer found errors; preview was not launched.'}
    & $flutter.Source test --no-pub --exclude-tags visual-capture
    if($LASTEXITCODE -ne 0){throw 'Flutter tests failed. No preview will be built.'}
    & $flutter.Source build windows --release --no-pub
    if($LASTEXITCODE -ne 0){throw 'Flutter release build failed.'}
}finally{Pop-Location}
}
& pwsh -NoProfile -File (Join-Path $project 'scripts/Install-WindowsIcon.ps1') -VerifyOnly
if($LASTEXITCODE -ne 0){throw 'Continuum native icon verification failed.'}
$release=Join-Path $project 'build\windows\x64\runner\Release'
$exe=Join-Path $release 'codex_resume_flutter.exe'
if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Flutter executable is missing.'}
foreach($required in @('flutter_windows.dll','data')){
    if(-not (Test-Path -LiteralPath (Join-Path $release $required))){
        throw "Flutter release payload incomplete: $required"
    }
}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$destinationCreated=$false
$archiveCreated=$false
$stagedZip=Join-Path $OutputDirectory ('.archive-'+[guid]::NewGuid().ToString('N')+'.zip')
try{
    # Creation must fail if another build claimed this destination after preflight.
    [void](New-Item -ItemType Directory -Path $destination -ErrorAction Stop)
    $destinationCreated=$true
    Copy-Item -Path (Join-Path $release '*') -Destination $destination -Recurse -Force -ErrorAction Stop
    $mustCopy=@('src/backend/Invoke-CodexJob.ps1','src/backend/CodexRunEngine.ps1','src/backend/CodexData.ps1',
        'src/backend/CodexJobStore.ps1','src/backend/CodexSessionRepository.ps1','src/backend/CodexRunActivity.ps1','src/backend/CodexUsage.js','src/backend/CodexQuotaContinuation.ps1','src/backend/CodexTerminalRun.ps1','src/backend/CodexRunJob.vbs')
    foreach($relative in $mustCopy){
        $from=Join-Path $root $relative
        if(-not (Test-Path -LiteralPath $from -PathType Leaf)){throw "Required worker file missing: $relative"}
        $target=Join-Path $destination $relative
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
        Copy-Item -LiteralPath $from -Destination $target -ErrorAction Stop
    }
    $componentNames=@('RuntimeBundle','OneTimeTasks','GitRepository','JobOutcomes','SettingsStore','SharedCodexSession')
    foreach($component in $componentNames){
        $source=Join-Path $root "components/$component"
        $target=Join-Path $destination "components/$component"
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
        Copy-Item -LiteralPath $source -Destination $target -Recurse -ErrorAction Stop
    }
    $bridgeFolder=Join-Path $destination 'src/desktop'
    [void](New-Item -ItemType Directory -Path $bridgeFolder -Force)
    Copy-Item -LiteralPath (Join-Path $project 'windows_bridge.ps1') -Destination $bridgeFolder -ErrorAction Stop
    Copy-Item -LiteralPath (Join-Path $project 'bridge') -Destination $bridgeFolder -Recurse -ErrorAction Stop
    Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $destination -ErrorAction Stop
    $sourceCommit=(& git -C $root rev-parse HEAD).Trim()
    if($LASTEXITCODE -ne 0){throw 'Cannot identify the source checkout for this preview.'}
    $sourceChanges=@(& git -C $root status --porcelain --untracked-files=no)
    if($LASTEXITCODE -ne 0){throw 'Cannot identify local source changes.'}
    [ordered]@{
        application='Continuum'
        version=$preview.Version
        sourceCommit=$sourceCommit
        sourceModified=($sourceChanges.Count -gt 0)
        builtAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'build-info.json') -Encoding utf8
    @'
CONTINUUM — UNSIGNED WINDOWS ENGINEERING PREVIEW
Provided for evaluation; see the release notes for known limitations.
No digital signatures or antivirus exclusions have been applied.
Requires PowerShell 7, Node.js, Git and Codex CLI (npm installation).
Uses Windows Task Scheduler and the bundled backend under src/backend.
Build identity is recorded in build-info.json; keep the complete package together.
Run codex_resume_flutter.exe. A working signed-in desktop is required.
No publisher authentication or full device acceptance is asserted.
'@ | Set-Content -LiteralPath (Join-Path $destination 'PREVIEW-NOTES.txt') -Encoding utf8
    $files=@(Get-ChildItem -LiteralPath $destination -File -Recurse |
        Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
        Sort-Object FullName)
    $lines=@(foreach($file in $files){
        $relative=[IO.Path]::GetRelativePath($destination,$file.FullName).Replace('\','/')
        "$(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 | Select-Object -ExpandProperty Hash)  $relative"
    })
    $lines | Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding utf8
    Compress-Archive -LiteralPath $destination -DestinationPath $stagedZip -CompressionLevel Optimal
    if(-not (Test-Path -LiteralPath $stagedZip -PathType Leaf)){throw 'Preview ZIP was not created.'}
    if((Get-Item -LiteralPath $stagedZip).Length -lt 1048576){throw 'Unexpectedly small Windows review package.'}
    # Extract and independently validate the actual distributed ZIP, not
    # merely the pre-compression source files. Paths are package-root-relative.
    $verify=Join-Path $OutputDirectory ('.verify-'+[guid]::NewGuid().ToString('N'))
    try{
        Expand-Archive -LiteralPath $stagedZip -DestinationPath $verify -ErrorAction Stop
        $extracted=Join-Path $verify $label
        $manifest=Get-Content -LiteralPath (Join-Path $extracted 'SHA256SUMS.txt') -ErrorAction Stop
        $actualFiles=@(Get-ChildItem -LiteralPath $extracted -Recurse -File |
            Where-Object { $_.Name -ne 'SHA256SUMS.txt' })
        if($manifest.Count -ne $actualFiles.Count){throw 'Packaged manifest file count mismatch.'}
        foreach($entry in $manifest){
            $parsed=[regex]::Match($entry,'^([0-9A-F]{64})  ([^\\]+)$')
            if(-not $parsed.Success){throw 'Malformed package checksum entry.'}
            $digest=$parsed.Groups[1].Value
            $relative=$parsed.Groups[2].Value
            if($relative.StartsWith('/') -or $relative.StartsWith('..') -or $relative.Contains('/../')){
                throw 'Unsafe package checksum path.'
            }
            $path=Join-Path $extracted $relative.Replace('/','\')
            if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Package file missing: $relative"}
            $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if($actual -cne $digest){throw "Package checksum failed: $relative"}
        }
    }finally{
        $resolvedVerify=[IO.Path]::GetFullPath($verify)
        if((Split-Path -Parent $resolvedVerify) -ine $OutputDirectory.TrimEnd('\') -or
            (Split-Path -Leaf $resolvedVerify) -notlike '.verify-*'){
            throw 'Refusing cleanup outside the package verification directory.'
        }
        if(Test-Path -LiteralPath $resolvedVerify){Remove-Item -LiteralPath $resolvedVerify -Recurse -Force -ErrorAction SilentlyContinue}
    }
    # Move without overwrite only after verifying the archive being published.
    [IO.File]::Move($stagedZip,$zip,$false)
    $archiveCreated=$true
    Write-Host "Verified $($manifest.Count) checksums from the extracted Windows package." -ForegroundColor Green
    Write-Host "Unsigned Windows Flutter review package: $zip" -ForegroundColor Green
    Write-Host "Standalone executable: $(Join-Path $destination 'codex_resume_flutter.exe')"
}catch{
    $resolvedDestination=[IO.Path]::GetFullPath($destination)
    if((Split-Path -Parent $resolvedDestination) -ine $OutputDirectory.TrimEnd('\') -or
        (Split-Path -Leaf $resolvedDestination) -cne $label){
        throw 'Refusing cleanup outside this preview destination.'
    }
    if($destinationCreated -and (Test-Path -LiteralPath $resolvedDestination)){
        Remove-Item -LiteralPath $resolvedDestination -Recurse -Force -ErrorAction SilentlyContinue
    }
    if($archiveCreated -and (Test-Path -LiteralPath $zip)){Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue}
    throw
}finally{
    if(Test-Path -LiteralPath $stagedZip){Remove-Item -LiteralPath $stagedZip -Force -ErrorAction SilentlyContinue}
}
