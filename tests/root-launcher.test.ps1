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
    Write-Host 'PASS — cached launch skips download; tampered download is rejected before extraction and launch.'
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
