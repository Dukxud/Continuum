# Install a repo-owned Windows icon after flutter create (generated windows/ is not tracked).
[CmdletBinding()]
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$source=Join-Path $project 'branding/continuum.ico'
$runner=Join-Path $project 'windows/runner'
$target=Join-Path $runner 'resources/app_icon.ico'
$rc=Join-Path $runner 'Runner.rc'
if(-not (Test-Path -LiteralPath $source -PathType Leaf)){throw 'Continuum native icon source is missing.'}
if(-not (Test-Path -LiteralPath $rc -PathType Leaf)){throw 'Flutter Windows runner not generated. Run flutter create first.'}
$rcText=Get-Content -LiteralPath $rc -Raw -ErrorAction Stop
if($rcText -cnotmatch 'IDI_APP_ICON\s+ICON\s+"resources[\\/]+app_icon\.ico"'){
    throw 'Windows Runner.rc does not reference the standard app_icon.ico resource.'
}
$bytes=[IO.File]::ReadAllBytes($source)
if($bytes.Length -lt 512 -or [BitConverter]::ToUInt16($bytes,0) -ne 0 -or
    [BitConverter]::ToUInt16($bytes,2) -ne 1 -or
    [BitConverter]::ToUInt16($bytes,4) -lt 4){
    throw 'Continuum icon does not contain a valid multi-size ICO header.'
}
if(-not $VerifyOnly){
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
    Copy-Item -LiteralPath $source -Destination $target -Force -ErrorAction Stop
}
if(-not (Test-Path -LiteralPath $target -PathType Leaf)){throw 'Generated Windows application icon is missing.'}
$expected=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$actual=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
if($expected -cne $actual){throw 'Generated runner icon differs from the pinned Continuum asset.'}
Write-Host "Continuum Windows icon $($VerifyOnly ? 'VERIFIED' : 'INSTALLED'): $target" -ForegroundColor Green
