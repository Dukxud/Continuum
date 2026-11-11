# Export AeroProgress independently of the scheduler.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,
      [switch]$Preview,
      [string]$CertificateThumbprint,
      [string]$TimestampServer)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $root 'legacy/winforms/VERSION') -Raw).Trim()
if(-not $Preview -and (-not $CertificateThumbprint -or -not $TimestampServer)){throw 'Public component distribution requires an authenticated code-signing certificate.'}
$name="AeroProgress-Component-v$version" + $(if($Preview){'-Preview'}else{''})
. (Join-Path $PSScriptRoot 'PackageWorkspace.ps1')
$workspace = New-PackageWorkspace -Name $name -OutputDirectory $OutputDirectory
try {
    $folder = $workspace.Directory
    foreach($file in @('AeroProgress.psm1','AeroProgress.psd1','README.md')){
        Copy-Item -LiteralPath (Join-Path $root "components/AeroProgress/$file") -Destination $folder
    }
    Copy-Item -LiteralPath (Join-Path $root 'assets/AeroBar.html') -Destination $folder
    Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $folder
    Copy-Item -LiteralPath (Join-Path $root 'AeroWebView2') -Destination $folder -Recurse
    if(-not $Preview){
        & (Join-Path $PSScriptRoot 'Sign-Release.ps1') -BundleDirectory $folder -CertificateThumbprint $CertificateThumbprint -TimestampServer $TimestampServer
    }else{
        [IO.File]::WriteAllText((Join-Path $folder 'UNSIGNED-REVIEW-ONLY.txt'),'Preview component is not publisher-signed. Use only for engineering review.',[Text.UTF8Encoding]::new($false))
    }
    & (Join-Path $PSScriptRoot 'Write-ReleaseHashes.ps1') -BundleDirectory $folder
    Complete-PackageWorkspace -Workspace $workspace
} finally {
    Remove-PackageWorkspace -Workspace $workspace
}
