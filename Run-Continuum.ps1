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
            'src/desktop/windows_bridge.ps1','src/backend/CodexRunEngine.ps1',
            'tests/flutter-port-source.test.ps1','tests/flutter-port-bridge.test.ps1')
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
        'tests/flutter-port-source.test.ps1','tests/flutter-port-bridge.test.ps1')){
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

if (-not $IsWindows) { throw 'Continuum runs on Windows x64.' }
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
$localExecutable = Join-Path $PSScriptRoot 'codex_resume_flutter.exe'
if ($plan.Mode -eq 'Package') {
    $manifest = Join-Path $PSScriptRoot 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        throw 'Local preview checksum manifest missing; refusing to launch.'
    }

    $prefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]@('/','\')) +
        [IO.Path]::DirectorySeparatorChar
    $entries = @(Get-Content -LiteralPath $manifest -ErrorAction Stop)
    if ($entries.Count -eq 0) { throw 'Local preview checksum manifest is empty.' }
    $verified = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $verifiedPaths = [Collections.Generic.List[string]]::new()
    foreach ($entry in $entries) {
        $match = [regex]::Match($entry, '^([0-9A-Fa-f]{64})  ([^\\]+)$')
        if (-not $match.Success) { throw 'Malformed local preview checksum entry.' }
        $relative = $match.Groups[2].Value.Replace('/', '\')
        $full = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $relative))
        if (-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
            -not $verified.Add($relative)) {
            throw 'Unsafe or duplicated local preview checksum path.'
        }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or
            (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ine $match.Groups[1].Value) {
            throw "Local preview checksum failed: $relative. Nothing was launched."
        }
        $verifiedPaths.Add($full)
    }
    foreach ($required in @('codex_resume_flutter.exe','flutter_windows.dll',
        'src\desktop\windows_bridge.ps1','src\backend\Invoke-CodexJob.ps1')) {
        if (-not $verified.Contains($required)) {
            throw "Local preview manifest does not cover required file: $required"
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'data') -PathType Container)) {
        throw 'Local preview missing Flutter data.'
    }
    # Unblock exactly the manifest-verified payload, not arbitrary extra files.
    # A previous CI artifact may have the launcher added as an external sidecar.
    foreach ($file in $verifiedPaths) {
        Unblock-File -LiteralPath $file -ErrorAction Stop
    }
    Write-Host 'Launching this verified local preview, not the pinned public release.'
    Start-Continuum -Executable $localExecutable
    return
}

if ($plan.Mode -eq 'Source') {
    $missing=@('flutter.bat','git.exe','node.exe' | Where-Object {-not (Get-Command $_ -ErrorAction SilentlyContinue)})
    if($missing.Count){
        throw "Building this source requires Flutter 3.47.9, Git, Node.js and Visual Studio's Desktop development with C++ workload. Missing from PATH: $($missing -join ', '). See docs/GETTING-STARTED.md."
    }
    Write-Host "Building the current source in $PSScriptRoot."
    Write-Host 'The Windows build requires Visual Studio Desktop development with C++; Flutter will report missing toolchain components.'
    $buildScripts=@(Get-ContinuumBuildScripts -Directory $PSScriptRoot)
    Write-Host "Trusting $($buildScripts.Count) build/runtime scripts in this source folder only; no execution-policy changes."
    foreach($file in $buildScripts){Unblock-File -LiteralPath $file -ErrorAction Stop}
    $output = Join-Path $env:LOCALAPPDATA ('Continuum\SourceBuilds\' + [guid]::NewGuid().ToString('N'))
    & (Join-Path $PSScriptRoot 'src\desktop\Build-WindowsPreview.ps1') -OutputDirectory $output
    if ($LASTEXITCODE -ne 0) { throw 'Source build failed; application not launched.' }
    $executables = @(Get-ChildItem -LiteralPath $output -File -Recurse -Filter 'codex_resume_flutter.exe')
    if ($executables.Count -ne 1) { throw "Expected one packaged executable; found $($executables.Count)." }
    Start-Continuum -Executable $executables[0].FullName
    return
}

# Fixed release identity: do not silently follow a moving "latest" download.
$package = 'Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW'
$downloadUrl = 'https://github.com/Dukxud/Continuum/releases/download/v0.1.0-preview.1/Continuum-Windows-v0.1.0%2B1-UNSIGNED-PREVIEW.zip'
$expectedSha256 = '08be6c6cd2bcbefcd8371348842ecc4ba04a565113f850654feeba6962a656f9'
$install = Join-Path $env:LOCALAPPDATA 'Continuum\Previews\v0.1.0-preview.1'
$executable = Join-Path (Join-Path $install $package) 'codex_resume_flutter.exe'
Write-Host 'Launcher-only folder: selecting the pinned public release v0.1.0-preview.1.'
Write-Host "Release ZIP SHA-256: $expectedSha256"

if (Test-Path -LiteralPath $executable -PathType Leaf) {
    Write-Host 'Opening the installed Continuum 0.1.0 Preview 1.'
    Start-Continuum -Executable $executable
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
    foreach ($relative in @(
        'codex_resume_flutter.exe',
        'flutter_windows.dll',
        'data',
        'src\desktop\windows_bridge.ps1',
        'src\backend\Invoke-CodexJob.ps1',
        'components\RuntimeBundle'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $relative))) {
            throw "Verified archive has an incomplete executable package: $relative"
        }
    }

    Write-Host 'SHA-256 verified. Unblocking files in this verified package only (no system policy change).'
    Get-ChildItem -LiteralPath $packageRoot -File -Recurse |
        Unblock-File -ErrorAction Stop

    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $install) -Force)
    if (Test-Path -LiteralPath $install) { throw "Preview cache was created concurrently: $install" }
    Move-Item -LiteralPath $unpacked -Destination $install -ErrorAction Stop
}
finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Start-Continuum -Executable $executable
