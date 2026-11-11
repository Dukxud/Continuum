$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/desktop/scripts/Get-PreviewMetadata.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('continuum-version-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixture)
try {
    $pubspec = Join-Path $fixture 'pubspec.yaml'
    Set-Content -LiteralPath $pubspec -Value "name: example`nversion: 1.2.3+42"
    $metadata = Get-ContinuumPreviewMetadata -PubspecPath $pubspec
    if ($metadata.Version -cne '1.2.3+42' -or $metadata.PackageName -cne 'Continuum-Windows-v1.2.3+42-UNSIGNED-PREVIEW') {
        throw 'Preview archive identity must match the Flutter version and build number.'
    }
    foreach ($invalid in @('version: ../../outside', 'version: latest', "version: 1.2.3`nversion: 4.5.6", 'name: missing')) {
        Set-Content -LiteralPath $pubspec -Value $invalid
        $rejected = $false
        try { Get-ContinuumPreviewMetadata -PubspecPath $pubspec | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw "Invalid version accepted: $invalid" }
    }
    Write-Host 'Preview package version and invalid-metadata rejection PASS.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ((Split-Path -Parent $resolved) -ine $temporaryRoot -or (Split-Path -Leaf $resolved) -notlike 'continuum-version-*') {
        throw 'Refusing cleanup outside the temporary version fixture.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
