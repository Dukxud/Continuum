# Windows launcher regression checks: cached launch and failed integrity verification.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This test requires Windows.' }

$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'Run-Continuum.ps1'
$batch = Join-Path $root 'Run-Continuum.cmd'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Missing root PowerShell launcher.' }
if (-not (Test-Path -LiteralPath $batch -PathType Leaf)) { throw 'Missing double-click root launcher.' }
if ((Get-Content -LiteralPath $batch -Raw) -notmatch 'Run-Continuum\.ps1') {
    throw 'Double-click entry point does not call the PowerShell launcher.'
}

$originalLocalAppData = $env:LOCALAPPDATA
$tempRoot = Join-Path $env:TEMP ('continuum-launcher-test-' + [guid]::NewGuid().ToString('N'))
$script:launches = [System.Collections.Generic.List[string]]::new()
try {
    $env:LOCALAPPDATA = Join-Path $tempRoot 'profile'
    $package = 'Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW'
    $exe = Join-Path $env:LOCALAPPDATA ('Continuum\Previews\v0.1.0-preview.1\' + $package + '\codex_resume_flutter.exe')
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $exe) -Force)
    Set-Content -LiteralPath $exe -Value 'test fixture, never executed'

    & {
        function Invoke-WebRequest { throw 'Cached launch unexpectedly used the network.' }
        function Start-Process {
            param([string]$FilePath,[string]$WorkingDirectory)
            $script:launches.Add($FilePath)
        }
        . $launcher
    }
    if ($script:launches.Count -ne 1 -or $script:launches[0] -cne $exe) {
        throw 'Cached launcher did not open the expected executable.'
    }

    Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'Continuum\Previews\v0.1.0-preview.1') -Recurse -Force
    $script:launches.Clear()
    & {
        function Invoke-WebRequest {
            param([string]$Uri,[string]$OutFile)
            [IO.File]::WriteAllText($OutFile, 'tampered download')
        }
        function Expand-Archive { throw 'A mismatched download must never be extracted.' }
        function Start-Process { throw 'A mismatched download must never be launched.' }
        $rejected = $false
        try { . $launcher }
        catch {
            if ($_.Exception.Message -notmatch 'SHA-256 does not match') { throw }
            $rejected = $true
        }
        if (-not $rejected) { throw 'Mismatched preview ZIP was accepted.' }
    }
    if ($script:launches.Count -ne 0) { throw 'Hash mismatch caused a launch.' }
    # A CI preview includes this same launcher, and must run the packaged
    # candidate rather than the pinned, older public release or cache.
    $local = Join-Path $tempRoot 'pr-preview'
    $localExe = Join-Path $local 'codex_resume_flutter.exe'
    $localBridge = Join-Path $local 'src\desktop\windows_bridge.ps1'
    $localWorker = Join-Path $local 'src\backend\Invoke-CodexJob.ps1'
    [void](New-Item -ItemType Directory -Path (Join-Path $local 'data'),(Split-Path -Parent $localBridge),(Split-Path -Parent $localWorker) -Force)
    Copy-Item -LiteralPath $launcher,$batch -Destination $local -ErrorAction Stop
    Set-Content -LiteralPath $localExe -Value 'CI preview fixture binary'
    Set-Content -LiteralPath (Join-Path $local 'flutter_windows.dll') -Value 'CI preview fixture DLL'
    Set-Content -LiteralPath $localBridge -Value 'CI preview fixture bridge'
    Set-Content -LiteralPath $localWorker -Value 'CI preview fixture worker'
    $manifest = @(
        Get-ChildItem -LiteralPath $local -Recurse -File |
            Sort-Object FullName |
            ForEach-Object {
                $relative = [IO.Path]::GetRelativePath($local,$_.FullName).Replace('\','/')
                "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)  $relative"
            }
    )
    $manifest | Set-Content -LiteralPath (Join-Path $local 'SHA256SUMS.txt') -Encoding utf8

    $script:launches.Clear()
    & {
        function Invoke-WebRequest { throw 'Packaged preview unexpectedly downloaded a release.' }
        function Start-Process {
            param([string]$FilePath,[string]$WorkingDirectory)
            $script:launches.Add($FilePath)
        }
        . (Join-Path $local 'Run-Continuum.ps1')
    }
    if($script:launches.Count -ne 1 -or $script:launches[0] -cne $localExe){
        throw 'Packaged launch did not prefer its local verified executable.'
    }

    Set-Content -LiteralPath $localBridge -Value 'TAMPERED'
    $script:launches.Clear()
    & {
        function Start-Process { throw 'A tampered packaged preview must never launch.' }
        $rejected = $false
        try { . (Join-Path $local 'Run-Continuum.ps1') }
        catch {
            if($_.Exception.Message -notmatch 'Local preview checksum failed'){throw}
            $rejected = $true
        }
        if(-not $rejected){throw 'A tampered local preview was accepted.'}
    }
    if($script:launches.Count -ne 0){throw 'Tampered packaged preview caused a launch.'}
    Write-Host 'PASS — cached launch, packaged PR launch, and tampered release/package rejection.'
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
