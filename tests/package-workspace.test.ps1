$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/PackageWorkspace.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('continuum-package-test-' + [guid]::NewGuid().ToString('N'))
$first = $null
$second = $null
try {
    $first = New-PackageWorkspace -Name 'Example-Preview' -OutputDirectory $fixture
    $second = New-PackageWorkspace -Name 'Example-Preview' -OutputDirectory $fixture
    if ($first.Root -eq $second.Root) { throw 'Concurrent builds share a staging directory.' }
    Set-Content -LiteralPath (Join-Path $first.Directory 'example.txt') -Value 'first build'
    Set-Content -LiteralPath (Join-Path $second.Directory 'example.txt') -Value 'second build'
    $archive = Complete-PackageWorkspace -Workspace $first
    $original = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    $rejected = $false
    try { Complete-PackageWorkspace -Workspace $second | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Publication overwrote an existing preview.' }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -cne $original) {
        throw 'Existing preview changed after a competing build.'
    }
    $rejected = $false
    try { New-PackageWorkspace -Name 'Example-Preview' -OutputDirectory $fixture | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Existing archive was not rejected before staging.' }
    Write-Host 'Independent staging and archive preservation PASS.'
} finally {
    if ($first) { Remove-PackageWorkspace -Workspace $first }
    if ($second) { Remove-PackageWorkspace -Workspace $second }
    $resolved = [IO.Path]::GetFullPath($fixture)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ((Split-Path -Parent $resolved) -ine $temporaryRoot -or (Split-Path -Leaf $resolved) -notlike 'continuum-package-test-*') {
        throw 'Refusing cleanup outside the package workspace fixture.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
