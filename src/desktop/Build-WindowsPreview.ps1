# Local, unsigned engineering preview only. Never publishes or bypasses AV.
[CmdletBinding()]
param(
    [string]$OutputDirectory=(Join-Path $HOME 'Downloads\Continuum-Preview'),
    [switch]$PackageVerifiedBuild
)

function Copy-ContinuumReleaseFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceDirectory,
          [Parameter(Mandatory)][string]$DestinationDirectory)
    if(-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)){
        throw 'Flutter release output directory is missing.'
    }
    $entries=@(Get-ChildItem -LiteralPath $SourceDirectory -Force -ErrorAction Stop)
    if(-not $entries.Count){throw 'Flutter release output is empty.'}
    foreach($entry in $entries){
        Copy-Item -LiteralPath $entry.FullName -Destination $DestinationDirectory -Recurse -Force -ErrorAction Stop
    }
}

function Test-ContinuumPackageParent {
    param([Parameter(Mandatory)][string]$ActualParent,
          [Parameter(Mandatory)][string]$ExpectedParent)
    # Both callers already resolved full paths. Trim both operands equally:
    # the parent of D:\.verify-<id> is D:\, not the truncated D:.
    $separators=[char[]]@('/','\')
    return [string]::Equals($ActualParent.TrimEnd($separators),
        $ExpectedParent.TrimEnd($separators),[StringComparison]::OrdinalIgnoreCase)
}

function New-ContinuumPackageArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceDirectory,
          [Parameter(Mandatory)][string]$DestinationPath)
    # Compress-Archive silently omits hidden payloads. The .NET archive API
    # preserves the complete enumerated tree and refuses an existing output.
    [IO.Compression.ZipFile]::CreateFromDirectory($SourceDirectory,$DestinationPath,
        [IO.Compression.CompressionLevel]::Optimal,$true)
}

$ErrorActionPreference='Stop'
$project=$PSScriptRoot
$root=[IO.Path]::GetFullPath((Join-Path $project '../..'))
if(-not $IsWindows){throw 'The preview package targets Windows.'}
if($PackageVerifiedBuild -and $env:GITHUB_ACTIONS -ne 'true'){
    throw 'Prevalidated-package mode is restricted to the isolated GitHub Actions build.'
}
. (Join-Path $project 'scripts/Invoke-PreviewBuild.ps1')
. (Join-Path $project 'scripts/Test-WindowsBuildPrerequisites.ps1')
. (Join-Path $project 'scripts/Assert-PreviewPackage.ps1')
. (Join-Path $project 'scripts/Get-PreviewMetadata.ps1')
$preview=Get-ContinuumPreviewMetadata -PubspecPath (Join-Path $project 'pubspec.yaml')
$label=$preview.PackageName
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$destination=Join-Path $OutputDirectory $label
$zip=Join-Path $OutputDirectory ($label+'.zip')
if((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $zip)){
    throw "Review package already exists: $destination or $zip"
}
if(-not $PackageVerifiedBuild){
    $tools=Assert-ContinuumWindowsBuildPrerequisites -ProjectDirectory $project -OutputDirectory $OutputDirectory
    Invoke-ContinuumPreviewBuild -ProjectDirectory $project -Tools $tools -BuildRelease
}else{
    Invoke-ContinuumBuildStep -Name 'Prevalidated package source integrity' `
        -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $root 'tests/flutter-port-source.test.ps1')) `
        -WorkingDirectory $project
}
$release=Join-Path $project 'build\windows\x64\runner\Release'
$exe=Join-Path $release 'codex_resume_flutter.exe'
if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Flutter executable is missing.'}
foreach($required in @('flutter_windows.dll','data')){
    if(-not (Test-Path -LiteralPath (Join-Path $release $required))){
        throw "Flutter release payload incomplete: $required"
    }
}
Invoke-ContinuumBuildStep -Name 'Compiled Windows icon verification' -FilePath (Join-Path $PSHOME 'pwsh.exe') `
    -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $root 'tests/flutter-windows-icon.test.ps1'),'-ExecutablePath',$exe) `
    -WorkingDirectory $project
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$destinationCreated=$false
$archiveCreated=$false
$stagedZip=Join-Path $OutputDirectory ('.archive-'+[guid]::NewGuid().ToString('N')+'.zip')
try{
    # Creation must fail if another build claimed this destination after preflight.
    [void](New-Item -ItemType Directory -Path $destination -ErrorAction Stop)
    $destinationCreated=$true
    Copy-ContinuumReleaseFiles -SourceDirectory $release -DestinationDirectory $destination
    $mustCopy=@('src/backend/Invoke-CodexJob.ps1','src/backend/CodexRunEngine.ps1','src/backend/CodexData.ps1',
        'src/backend/CodexJobStore.ps1','src/backend/CodexSessionRepository.ps1','src/backend/CodexRepositoryEvidence.ps1','src/backend/CodexRunActivity.ps1','src/backend/CodexUsage.js','src/backend/CodexCli.ps1','src/backend/CodexQuotaContinuation.ps1','src/backend/CodexTerminalRun.ps1','src/backend/CodexRunJob.vbs')
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
    $packageScripts=Join-Path $bridgeFolder 'scripts'
    [void](New-Item -ItemType Directory -Path $packageScripts -Force)
    Copy-Item -LiteralPath (Join-Path $project 'scripts/Assert-PreviewPackage.ps1') -Destination $packageScripts -ErrorAction Stop
    Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $destination -ErrorAction Stop
    # Ship the same root-level launcher that source-ZIP users already know.
    # When packaged beside an EXE it verifies and launches this exact build.
    foreach($entry in @('Run-Continuum.cmd','Run-Continuum.ps1')){
        $from=Join-Path $root $entry
        if(-not (Test-Path -LiteralPath $from -PathType Leaf)){
            throw "Required preview launcher missing: $entry"
        }
        Copy-Item -LiteralPath $from -Destination (Join-Path $destination $entry) -ErrorAction Stop
    }
    $sourceIdentity=Get-ContinuumSourceIdentity -SourceDirectory $root
    [ordered]@{
        application='Continuum'
        version=$preview.Version
        sourceCommit=$sourceIdentity.SourceCommit
        sourceModified=$sourceIdentity.SourceModified
        sourceArchive=$sourceIdentity.SourceArchive
        builtAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'build-info.json') -Encoding utf8
    @'
CONTINUUM — UNSIGNED WINDOWS ENGINEERING PREVIEW
Provided for evaluation; see the release notes for known limitations.
No digital signatures or antivirus exclusions have been applied.
Requires PowerShell 7.4 or newer, Node.js, Git and Codex CLI (native or npm installation).
Also requires Microsoft Visual C++ v14 Redistributable (x64):
https://aka.ms/vc14/vc_redist.x64.exe
Uses Windows Task Scheduler and the bundled backend under src/backend.
Build identity is recorded in build-info.json; keep the complete package together.
Run Run-Continuum.cmd in this folder. It verifies and launches this exact preview.
Directly running codex_resume_flutter.exe is also possible.
A working signed-in desktop is required.
No publisher authentication or full device acceptance is asserted.
'@ | Set-Content -LiteralPath (Join-Path $destination 'PREVIEW-NOTES.txt') -Encoding utf8
    $files=@(Get-ChildItem -LiteralPath $destination -File -Recurse -Force |
        Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
        Sort-Object FullName)
    $lines=@(foreach($file in $files){
        $relative=[IO.Path]::GetRelativePath($destination,$file.FullName).Replace('\','/')
        "$(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 | Select-Object -ExpandProperty Hash)  $relative"
    })
    $lines | Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding utf8
    $verifiedPackage=Assert-ContinuumPreviewPackage -Directory $destination
    New-ContinuumPackageArchive -SourceDirectory $destination -DestinationPath $stagedZip
    if(-not (Test-Path -LiteralPath $stagedZip -PathType Leaf)){throw 'Preview ZIP was not created.'}
    if((Get-Item -LiteralPath $stagedZip).Length -lt 1048576){throw 'Unexpectedly small Windows review package.'}
    # Extract and independently validate the actual distributed ZIP, not
    # merely the pre-compression source files. Paths are package-root-relative.
    $verify=Join-Path $OutputDirectory ('.verify-'+[guid]::NewGuid().ToString('N'))
    try{
        Expand-Archive -LiteralPath $stagedZip -DestinationPath $verify -ErrorAction Stop
        $extracted=Join-Path $verify $label
        $extractedPackage=Assert-ContinuumPreviewPackage -Directory $extracted
        if($extractedPackage.FileCount -ne $verifiedPackage.FileCount){throw 'Extracted package differs from the staged package.'}
    }finally{
        $resolvedVerify=[IO.Path]::GetFullPath($verify)
        if(-not (Test-ContinuumPackageParent -ActualParent (Split-Path -Parent $resolvedVerify) -ExpectedParent $OutputDirectory) -or
            (Split-Path -Leaf $resolvedVerify) -notlike '.verify-*'){
            throw 'Refusing cleanup outside the package verification directory.'
        }
        if(Test-Path -LiteralPath $resolvedVerify){Remove-Item -LiteralPath $resolvedVerify -Recurse -Force -ErrorAction SilentlyContinue}
    }
    # Move without overwrite only after verifying the archive being published.
    [IO.File]::Move($stagedZip,$zip,$false)
    $archiveCreated=$true
    Write-Host "Verified $($extractedPackage.FileCount) checksums from the extracted Windows package." -ForegroundColor Green
    Write-Host "Unsigned Windows Flutter review package: $zip" -ForegroundColor Green
    Write-Host "Standalone executable: $(Join-Path $destination 'codex_resume_flutter.exe')"
}catch{
    $resolvedDestination=[IO.Path]::GetFullPath($destination)
    if(-not (Test-ContinuumPackageParent -ActualParent (Split-Path -Parent $resolvedDestination) -ExpectedParent $OutputDirectory) -or
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
