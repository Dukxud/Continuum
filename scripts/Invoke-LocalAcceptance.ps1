# One deterministic, manual Windows acceptance entrypoint. Never calls CI.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ExpectedCommit)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $root ('QA-results-local-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
Write-Host 'BLACK-PUDDLE — LOCAL ACCEPTANCE START' -ForegroundColor Magenta
try {
    if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 on Windows is required.' }
    $actual = (& git -C $root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -cne $ExpectedCommit) { throw "Source commit mismatch: $actual" }
    if (@(& git -C $root status --porcelain --untracked-files=no).Count -gt 0) { throw 'Tracked source has local edits; isolated candidate no longer matches the reviewed commit.' }
    $null = Get-Command node.exe -ErrorAction Stop
    $null = Get-Command pwsh.exe -ErrorAction Stop
    [void](New-Item -ItemType Directory -Path $logRoot -Force)
    $source = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1','.psd1') })
    $syntax = @(
        foreach ($file in $source) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
            foreach ($e in @($errors)) {
                if ($e) { "$($file.FullName):$($e.Extent.StartLineNumber) $($e.Message)" }
            }
        }
    )
    if ($syntax.Count -gt 0) { throw "PowerShell syntax errors:`n$($syntax -join [Environment]::NewLine)" }
    Write-Host "PASS — parsed $($source.Count) PowerShell source files" -ForegroundColor Green
    $tests = @(Get-ChildItem -LiteralPath (Join-Path $root 'tests') -File | Where-Object { $_.Name -match '\.test\.(ps1|js)$' } | Sort-Object Name)
    if ($tests.Count -lt 36) { throw "Test discovery incomplete: $($tests.Count) files (expected at least 36)." }
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($test in $tests) {
        $log = Join-Path $logRoot ($test.Name + '.log')
        Write-Host "RUNNING — $($test.Name)" -ForegroundColor Cyan
        $code = 1
        try {
            if ($test.Extension -eq '.js') {
                & node.exe --test $test.FullName *>&1 | Out-File -LiteralPath $log -Encoding utf8
            } else {
                & pwsh.exe -NoProfile -STA -File $test.FullName *>&1 | Out-File -LiteralPath $log -Encoding utf8
            }
            $code = [int]$LASTEXITCODE
        } catch {
            $_ | Out-String | Out-File -LiteralPath $log -Encoding utf8 -Append
        }
        $results.Add([pscustomobject]@{Name=$test.Name;Exit=$code;Log=$log})
        Write-Host "$(if($code -eq 0){'PASS'}else{'FAIL'}) — $($test.Name)" -ForegroundColor $(if($code -eq 0){'Green'}else{'Red'})
    }
    $failed = @($results | Where-Object Exit -ne 0)
    Write-Host "RESULT — $($results.Count - $failed.Count) PASS / $($failed.Count) FAIL / $($results.Count) TEST FILES" -ForegroundColor $(if($failed.Count){'Red'}else{'Green'})
    foreach ($f in $failed) {
        Write-Host "FAILURE — $($f.Name)" -ForegroundColor Red
        Get-Content -LiteralPath $f.Log -Tail 40
    }
    $visual = Join-Path $logRoot 'dashboard-visuals.test.ps1.log'
    if (Test-Path -LiteralPath $visual) {
        Get-Content -LiteralPath $visual | Where-Object { $_ -match 'WPF pixel evidence|WPF time-fill sweep|WPF compositor' }
    }
    Write-Host "COMPLETE LOGS — $logRoot" -ForegroundColor Cyan
    if ($failed.Count -gt 0) { exit 1 }
    exit 0
} catch {
    Write-Host "ACCEPTANCE ERROR — $($_.Exception.Message)" -ForegroundColor Red
    if (Test-Path -LiteralPath $logRoot) { Write-Host "LOGS — $logRoot" -ForegroundColor Cyan }
    exit 1
} finally {
    Write-Host 'BLACK-PUDDLE — LOCAL ACCEPTANCE END' -ForegroundColor Magenta
}
