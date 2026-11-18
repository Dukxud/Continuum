# Launch the pinned public preview from a source archive, or build a Git checkout.
# Neither mode changes the machine or user PowerShell execution policy.
[CmdletBinding()]
param([switch]$BuildFromSource)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'Continuum runs on Windows x64.' }

function Start-Continuum {
    param([Parameter(Mandatory)][string]$Executable)
    Start-Process -FilePath $Executable -WorkingDirectory (Split-Path -Parent $Executable)
}

if ($BuildFromSource) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git') -PathType Container)) {
        throw 'Building requires a Git checkout, not a GitHub source ZIP. See docs/GETTING-STARTED.md.'
    }
    if (-not (Get-Command flutter.bat -ErrorAction SilentlyContinue)) {
        throw 'Flutter is required to build the current checkout. See docs/GETTING-STARTED.md.'
    }
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

if (Test-Path -LiteralPath $executable -PathType Leaf) {
    Write-Host 'Opening the installed Continuum 0.1.0 Preview 1 (not the source checkout).'
    Start-Continuum -Executable $executable
    return
}
if (Test-Path -LiteralPath $install) {
    throw "Preview cache is incomplete: $install. Inspect it before removing or replacing it."
}

Write-Host "Downloading the pinned, unsigned Continuum preview from GitHub (not compiling this checkout)."
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
