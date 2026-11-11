# Standalone reusable-kit ZIP: independent PowerShell modules, no scheduler runtime.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,
      [switch]$Preview,
      [string]$CertificateThumbprint,
      [string]$TimestampServer)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $root 'legacy/winforms/VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid VERSION file.'}
if(-not $Preview -and (-not $CertificateThumbprint -or -not $TimestampServer)){
    throw 'Standalone production components require verified code signing.'
}
$name="ReusableComponents-v$version" + $(if($Preview){'-Preview'}else{''})
. (Join-Path $PSScriptRoot 'PackageWorkspace.ps1')
$workspace = New-PackageWorkspace -Name $name -OutputDirectory $OutputDirectory
try {
    $folder = $workspace.Directory
    $componentTarget = Join-Path $folder 'components'
    [void](New-Item -ItemType Directory -Path $componentTarget)
    $modules = @(Get-ChildItem -LiteralPath (Join-Path $root 'components') -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ($_.Name + '.psd1')) -PathType Leaf })
    foreach ($module in $modules) {
        Copy-Item -LiteralPath $module.FullName -Destination $componentTarget -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $root 'components/README.md') -Destination $componentTarget
    # Make each module folder independently portable: AeroProgress carries its
    # renderer and the required Microsoft SDK DLLs beside its own module.
    $aeroFolder=Join-Path $folder 'components/AeroProgress'
    Copy-Item -LiteralPath (Join-Path $root 'AeroWebView2') -Destination $aeroFolder -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'assets/AeroBar.html') -Destination (Join-Path $aeroFolder 'AeroBar.html')
    Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $folder
    Copy-Item -LiteralPath (Join-Path $root 'legacy/winforms/VERSION') -Destination $folder
    if(-not $Preview){
        & (Join-Path $PSScriptRoot 'Sign-Release.ps1') -BundleDirectory $folder -CertificateThumbprint $CertificateThumbprint -TimestampServer $TimestampServer
    }else{
        [IO.File]::WriteAllText((Join-Path $folder 'UNSIGNED-REVIEW-ONLY.txt'),'Standalone components engineering preview: scripts are not publisher-signed.',[Text.UTF8Encoding]::new($false))
    }
    & (Join-Path $PSScriptRoot 'Write-ReleaseHashes.ps1') -BundleDirectory $folder
    Complete-PackageWorkspace -Workspace $workspace
} finally {
    Remove-PackageWorkspace -Workspace $workspace
}
