# Launch the application associated with this folder.
# No launch mode changes the machine or user PowerShell execution policy.
[CmdletBinding()]
param([switch]$BuildFromSource)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ContinuumLaunchPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[switch]$BuildFromSource)
    $base=[IO.Path]::GetFullPath($Directory)
    $executable=Join-Path $base 'codex_resume_flutter.exe'
    $sourceMarkers=@('src/desktop/Build-WindowsPreview.ps1',
        'src/desktop/pubspec.yaml','src/desktop/lib/main.dart')
    $hasSource=@($sourceMarkers | Where-Object {Test-Path -LiteralPath (Join-Path $base $_)}).Count -gt 0
    if($BuildFromSource -or $hasSource){
        $required=$sourceMarkers+@('src/desktop/pubspec.lock',
            'src/desktop/scripts/Get-PreviewMetadata.ps1',
            'src/desktop/scripts/Initialize-WindowsRunner.ps1',
            'src/desktop/scripts/Install-WindowsIcon.ps1',
            'src/desktop/scripts/Test-WindowsBuildPrerequisites.ps1',
            'src/desktop/scripts/Invoke-PreviewBuild.ps1',
            'src/desktop/scripts/BuildProcessOwner.ps1',
            'src/desktop/scripts/Assert-PreviewPackage.ps1',
            'src/desktop/windows_bridge.ps1','src/backend/CodexRunEngine.ps1',
            'tests/flutter-port-source.test.ps1','tests/flutter-port-bridge.test.ps1',
            'tests/windows-task-host.test.ps1','tests/flutter-windows-icon.test.ps1')
        $missing=@($required | Where-Object {-not (Test-Path -LiteralPath (Join-Path $base $_) -PathType Leaf)})
        if($missing.Count){
            throw "Incomplete source tree. Restore the complete source ZIP or checkout. Missing: $($missing -join ', ')."
        }
        return [pscustomobject]@{Mode='Source';Directory=$base;Executable=$null}
    }
    # Packaged runtime folders contain backend scripts but no Flutter project.
    if(Test-Path -LiteralPath $executable -PathType Leaf){
        return [pscustomobject]@{Mode='Package';Directory=$base;Executable=$executable}
    }
    foreach($relative in @('src/desktop/windows_bridge.ps1','src/backend/CodexRunEngine.ps1',
        'flutter_windows.dll','data')){
        if(Test-Path -LiteralPath (Join-Path $base $relative)){
            throw 'Incomplete application package: codex_resume_flutter.exe is missing. Extract the complete package.'
        }
    }
    return [pscustomobject]@{Mode='PinnedRelease';Directory=$base;Executable=$null}
}

function Get-ContinuumBuildScripts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)
    $base=[IO.Path]::GetFullPath($Directory)
    function Assert-LocalSourcePath([string]$Relative){
        $current=$base
        foreach($part in @('')+@($Relative -split '[/\\]')){
            if($part){$current=Join-Path $current $part}
            $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw "Source build will not unblock or follow linked paths: $current"
            }
        }
        return $current
    }
    $files=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($relative in @('Run-Continuum.cmd','Run-Continuum.ps1',
        'src/desktop/Build-WindowsPreview.ps1','src/desktop/windows_bridge.ps1',
        'src/desktop/scripts/Get-PreviewMetadata.ps1',
        'src/desktop/scripts/Initialize-WindowsRunner.ps1',
        'src/desktop/scripts/Install-WindowsIcon.ps1',
        'src/desktop/scripts/Test-WindowsBuildPrerequisites.ps1',
        'src/desktop/scripts/Invoke-PreviewBuild.ps1',
        'src/desktop/scripts/BuildProcessOwner.ps1',
        'src/desktop/scripts/Assert-PreviewPackage.ps1',
        'tests/flutter-port-source.test.ps1','tests/flutter-port-bridge.test.ps1',
        'tests/windows-task-host.test.ps1','tests/flutter-windows-icon.test.ps1')){
        [void]$files.Add((Assert-LocalSourcePath $relative))
    }
    foreach($relative in @('src/backend','src/desktop/bridge','components/RuntimeBundle',
        'components/OneTimeTasks','components/GitRepository','components/JobOutcomes',
        'components/SettingsStore','components/SharedCodexSession')){
        $folder=Assert-LocalSourcePath $relative
        # No recursion into generated files, external trees, or user downloads.
        foreach($file in @(Get-ChildItem -LiteralPath $folder -File -Force)){
            if($file.Extension -notin @('.ps1','.psm1','.psd1','.vbs')){continue}
            if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw "Source build will not unblock or follow linked scripts: $($file.FullName)"
            }
            [void]$files.Add($file.FullName)
        }
    }
    return @($files | Sort-Object)
}

function Get-ContinuumPackageVerifier {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[switch]$RequireManifest)
    $base=[IO.Path]::GetFullPath($Directory)
    $relative='src/desktop/scripts/Assert-PreviewPackage.ps1'
    $current=$base
    foreach($part in @('')+@($relative.Split('/'))){
        if($part){$current=Join-Path $current $part}
        if(-not (Test-Path -LiteralPath $current)){
            throw "The launcher package verifier is missing: $relative. Extract the complete source or application package together; do not copy the launcher files alone."
        }
        $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw "The launcher will not load a verifier through a linked path: $current"
        }
    }
    if($item.PSIsContainer -or $item.Length -eq 0){throw 'The launcher package verifier is empty or invalid. Extract the complete package again.'}
    if($RequireManifest){
        $manifest=Join-Path $base 'SHA256SUMS.txt'
        if(-not (Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'Preview checksum manifest missing; extract the complete package.'}
        if(((Get-Item -LiteralPath $manifest -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'The launcher will not read a linked checksum manifest.'
        }
        $matches=@([IO.File]::ReadAllLines($manifest) | Where-Object {$_ -match ('^[0-9A-Fa-f]{64}  '+[regex]::Escape($relative)+'$')})
        if($matches.Count -ne 1){throw 'Preview checksum manifest must cover the package verifier exactly once.'}
        if((Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash -ine $matches[0].Substring(0,64)){
            throw 'Preview package checksum failed: src/desktop/scripts/Assert-PreviewPackage.ps1. Nothing was launched.'
        }
    }
    return $current
}

if (-not $IsWindows) { throw 'Continuum runs on Windows x64.' }
if($PSVersionTable.PSVersion -lt [version]'7.4'){
    throw "Continuum requires PowerShell 7.4 or newer; this launcher is running $($PSVersionTable.PSVersion) from $PSHOME. Put a current x64 PowerShell 7 installation first on PATH and reopen Run-Continuum.cmd."
}
$plan=Get-ContinuumLaunchPlan -Directory $PSScriptRoot -BuildFromSource:$BuildFromSource

function Start-Continuum {
    param([Parameter(Mandatory)][string]$Executable)
    $packageDirectory=Split-Path -Parent $Executable
    Write-Host "Executable: $Executable"
    $buildInfo=Join-Path $packageDirectory 'build-info.json'
    if(Test-Path -LiteralPath $buildInfo -PathType Leaf){
        $identity=Get-Content -LiteralPath $buildInfo -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        $source=if($identity['sourceCommit']){[string]$identity['sourceCommit']}
            elseif($identity['sourceArchive']){'source archive; commit unavailable'}else{'not recorded'}
        $modified=if($null -eq $identity['sourceModified']){'unknown'}else{[string]$identity['sourceModified']}
        Write-Host "Build: $($identity['version']); source: $source; modified: $modified"
    }else{Write-Host 'Build identity: build-info.json is not present.'}
    if(-not [string]::IsNullOrEmpty($env:CODEX_SCHEDULER_SOURCE)){
        $backend=[IO.Path]::GetFullPath($env:CODEX_SCHEDULER_SOURCE,$packageDirectory)
        Write-Host "Backend source: $backend (CODEX_SCHEDULER_SOURCE override)"
    }else{Write-Host "Backend source: $packageDirectory (bundled)"}
    Start-Process -FilePath $Executable -WorkingDirectory $packageDirectory
}

# Packaged CI previews ship this same launcher beside the executable.
# A local, manifest-verified package takes precedence over the pinned public
# release; otherwise reviewing a PR would silently launch old application code.
if ($plan.Mode -eq 'Package') {
    # Verify this one known helper before loading it from a downloaded package.
    $verifier=Get-ContinuumPackageVerifier -Directory $PSScriptRoot -RequireManifest
    Unblock-File -LiteralPath $verifier -ErrorAction Stop
    . $verifier
    $verified=Assert-ContinuumPreviewPackage -Directory $PSScriptRoot -Profile Current
    foreach($file in $verified.VerifiedPaths){Unblock-File -LiteralPath $file -ErrorAction Stop}
    Write-Host "Launching this verified local preview ($($verified.FileCount) files)."
    Start-Continuum -Executable $verified.Executable
    return
}

if ($plan.Mode -eq 'Source') {
    Write-Host "Building the current source in $PSScriptRoot."
    Write-Host 'Checking Windows link capability, the pinned Flutter SDK and C++ build tools before the build.'
    $buildScripts=@(Get-ContinuumBuildScripts -Directory $PSScriptRoot)
    Write-Host "Trusting $($buildScripts.Count) build/runtime scripts in this source folder only; no execution-policy changes."
    foreach($file in $buildScripts){Unblock-File -LiteralPath $file -ErrorAction Stop}
    if([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)){throw 'LOCALAPPDATA is missing. Reopen Run-Continuum.cmd in your normal Windows account.'}
    $output = Join-Path $env:LOCALAPPDATA ('Continuum\SourceBuilds\' + [guid]::NewGuid().ToString('N'))
    & (Join-Path $PSScriptRoot 'src\desktop\Build-WindowsPreview.ps1') -OutputDirectory $output
    $executables = @(Get-ChildItem -LiteralPath $output -File -Recurse -Filter 'codex_resume_flutter.exe')
    if ($executables.Count -ne 1) { throw "Expected one packaged executable; found $($executables.Count)." }
    . (Get-ContinuumPackageVerifier -Directory $PSScriptRoot)
    $verified=Assert-ContinuumPreviewPackage -Directory $executables[0].Directory.FullName -Profile Current
    Start-Continuum -Executable $verified.Executable
    return
}

# Fixed release identity: do not silently follow a moving "latest" download.
$package = 'Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW'
$downloadUrl = 'https://github.com/Dukxud/Continuum/releases/download/v0.1.0-preview.1/Continuum-Windows-v0.1.0%2B1-UNSIGNED-PREVIEW.zip'
$expectedSha256 = '08be6c6cd2bcbefcd8371348842ecc4ba04a565113f850654feeba6962a656f9'
if([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)){throw 'LOCALAPPDATA is missing. Reopen Run-Continuum.cmd in your normal Windows account.'}
$verifier=Get-ContinuumPackageVerifier -Directory $PSScriptRoot
Unblock-File -LiteralPath $verifier -ErrorAction Stop
. $verifier
$install = Join-Path $env:LOCALAPPDATA 'Continuum\Previews\v0.1.0-preview.1'
$executable = Join-Path (Join-Path $install $package) 'codex_resume_flutter.exe'
Write-Host 'Launcher-only folder: selecting the pinned public release v0.1.0-preview.1.'
Write-Host "Release ZIP SHA-256: $expectedSha256"

if (Test-Path -LiteralPath $executable -PathType Leaf) {
    $verified=Assert-ContinuumPreviewPackage -Directory (Split-Path -Parent $executable) -Profile PinnedPreview1
    foreach($file in $verified.VerifiedPaths){Unblock-File -LiteralPath $file -ErrorAction Stop}
    Write-Host 'Opening the installed Continuum 0.1.0 Preview 1.'
    Start-Continuum -Executable $verified.Executable
    return
}
if (Test-Path -LiteralPath $install) {
    throw "Preview cache is incomplete: $install. Inspect it before removing or replacing it."
}

Write-Host 'Downloading the pinned, unsigned Continuum 0.1.0 Preview 1 from GitHub.'
$staging = Join-Path $env:TEMP ('Continuum-Launcher-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $staging -ErrorAction Stop)
try {
    $archive = Join-Path $staging 'preview.zip'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archive -ErrorAction Stop
    $actualSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($actualSha256 -ine $expectedSha256) {
        throw 'Release ZIP SHA-256 does not match the pinned published digest. Nothing was launched.'
    }

    $unpacked = Join-Path $staging 'unpacked'
    Expand-Archive -LiteralPath $archive -DestinationPath $unpacked -ErrorAction Stop
    $packageRoot = Join-Path $unpacked $package
    $verified=Assert-ContinuumPreviewPackage -Directory $packageRoot -Profile PinnedPreview1
    Write-Host 'SHA-256 verified. Unblocking files in this verified package only (no system policy change).'
    foreach($file in $verified.VerifiedPaths){Unblock-File -LiteralPath $file -ErrorAction Stop}

    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $install) -Force)
    if (Test-Path -LiteralPath $install) { throw "Preview cache was created concurrently: $install" }
    Move-Item -LiteralPath $unpacked -Destination $install -ErrorAction Stop
}
finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$verified=Assert-ContinuumPreviewPackage -Directory (Split-Path -Parent $executable) -Profile PinnedPreview1
Start-Continuum -Executable $verified.Executable
