# The Flutter package version is the authority for the native app and its ZIP.
function Get-ContinuumPreviewMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PubspecPath)

    $pubspec = Get-Content -LiteralPath $PubspecPath -Raw -ErrorAction Stop
    $versionMatches = [regex]::Matches($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+(?:\+\d+)?)\s*$')
    if ($versionMatches.Count -ne 1) {
        throw 'pubspec.yaml must contain one numeric version, optionally followed by a build number.'
    }
    $version = $versionMatches[0].Groups[1].Value
    [pscustomobject]@{
        Version = $version
        PackageName = "Continuum-Windows-v$version-UNSIGNED-PREVIEW"
    }
}
