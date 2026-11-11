# Windows regression suite shared by local development and CI.
[CmdletBinding()]
param(
    [ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ExpectedCommit,
    [ValidateRange(30,1800)][int]$TestTimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$originalDirectory = (Get-Location).Path
$logRoot = Join-Path $root ('QA-results-local-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
Write-Host 'Continuum — Windows acceptance start' -ForegroundColor Magenta
try {
    if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 on Windows is required.' }
    Set-Location -LiteralPath $root
    $null = Get-Command git.exe -ErrorAction Stop
    $actual = (& git -C $root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the checkout.' }
    if ($ExpectedCommit) {
        if ($actual -cne $ExpectedCommit) { throw "Source commit mismatch: $actual" }
        if (@(& git -C $root status --porcelain --untracked-files=no).Count -gt 0) { throw 'Tracked source has local edits; candidate no longer matches the requested commit.' }
    }
    $null = Get-Command node.exe -ErrorAction Stop
    $null = Get-Command pwsh.exe -ErrorAction Stop
    [void](New-Item -ItemType Directory -Path $logRoot -Force)
    $source = @(& git -C $root ls-files -- '*.ps1' '*.psm1' '*.psd1' |
        ForEach-Object { Get-Item -LiteralPath (Join-Path $root $_) -ErrorAction Stop })
    if ($LASTEXITCODE -ne 0 -or $source.Count -eq 0) { throw 'Cannot discover tracked PowerShell source.' }
    $syntax = @(
        foreach ($file in $source) {
            # ParseInput distinguishes file-access failures from syntax errors.
            # A security product may remove a file after Git/status enumeration.
            try { $contents = [IO.File]::ReadAllText($file.FullName) }
            catch {
                throw "SOURCE ACCESS FAILURE: $($file.FullName) ($($_.Exception.GetType().Name)): $($_.Exception.Message)"
            }
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                $contents,$file.FullName,[ref]$tokens,[ref]$errors)
            foreach ($e in @($errors)) {
                if ($e) { "$($file.FullName):$($e.Extent.StartLineNumber) $($e.Message)" }
            }
            # Keep the same reserved-variable check as the GitHub workflow.
            $reserved = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -ieq 'host'
            }, $true))
            foreach ($node in $reserved) {
                "$($file.FullName):$($node.Extent.StartLineNumber) Reserved Host assignment"
            }
        }
    )
    if ($syntax.Count -gt 0) { throw "PowerShell syntax errors:`n$($syntax -join [Environment]::NewLine)" }
    # Catch disappearances between the initial Git check and source discovery:
    # missing files must never make the acceptance suite appear smaller/green.
    $postScan = @(& git -C $root status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0 -or ($ExpectedCommit -and $postScan.Count -gt 0)) {
        throw "SOURCE INTEGRITY FAILURE during scan: $($postScan -join '; ')"
    }
    Write-Host "PASS — parsed $($source.Count) PowerShell source files" -ForegroundColor Green
    # Fresh checkouts lack the WebView2 SDK. Bootstrap only missing files
    # using the pinned download and archive SHA-256 in Prepare-AeroWebView2.ps1.
    $sdkDirectory = Join-Path $root 'AeroWebView2'
    $sdkFiles = @('Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.WinForms.dll','WebView2Loader.dll')
    $missingSdk = @($sdkFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $sdkDirectory $_) -PathType Leaf) })
    if ($missingSdk.Count -gt 0) {
        Write-Host "Preparing missing WebView2 SDK files: $($missingSdk -join ', ')" -ForegroundColor Cyan
        try { & (Join-Path $PSScriptRoot 'Prepare-AeroWebView2.ps1') }
        catch { throw "WebView2 SDK preparation failed: $($_.Exception.Message)" }
        $missingSdk = @($sdkFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $sdkDirectory $_) -PathType Leaf) })
        if ($missingSdk.Count -gt 0) { throw "WebView2 SDK remains incomplete: $($missingSdk -join ', ')" }
    }
    Write-Host 'PASS — WebView2 SDK dependencies available' -ForegroundColor Green
    $tests = @(Get-ChildItem -LiteralPath (Join-Path $root 'tests') -File | Where-Object { $_.Name -match '\.test\.(ps1|js|mjs)$' } | Sort-Object Name)
    # Git-tracked test inventory is authoritative in both local and manual CI.
    # Do not silently pass after an antivirus deletion or stale workflow list.
    $expected = @(& git -C $root ls-files -- tests | Where-Object {
        $_ -match '^tests/[^/]+\.test\.(?:ps1|js|mjs)$'
    } | ForEach-Object { [IO.Path]::GetFileName($_) } | Sort-Object)
    if ($LASTEXITCODE -ne 0 -or $expected.Count -eq 0) { throw 'Could not discover the tracked test inventory.' }
    $actual = @($tests | ForEach-Object Name)
    $missing = @($expected | Where-Object { $actual -cnotcontains $_ })
    $extra = @($actual | Where-Object { $expected -cnotcontains $_ })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw "Test inventory mismatch. Missing: $($missing -join ', '); Unexpected: $($extra -join ', ')"
    }
    Write-Host "PASS — tracked test inventory: $($expected.Count) exact files" -ForegroundColor Green
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($test in $tests) {
        $log = Join-Path $logRoot ($test.Name + '.log')
        Write-Host "RUNNING — $($test.Name)" -ForegroundColor Cyan
        $code = 1
        $stdout = ''
        $stderr = ''
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = if ($test.Extension -in @('.js','.mjs')) { 'node.exe' } else { 'pwsh.exe' }
        $arguments = if ($test.Extension -in @('.js','.mjs')) {
            @('--test', $test.FullName)
        } else {
            @('-NoProfile', '-STA', '-File', $test.FullName)
        }
        foreach ($argument in $arguments) { [void]$startInfo.ArgumentList.Add($argument) }
        # Each test receives empty application/session state, including tests
        # that exercise the real read-only bridge or open the legacy GUI.
        $testProfile = Join-Path $logRoot ('profiles/' + $test.BaseName)
        $localProfile = Join-Path $testProfile 'local'
        $codexProfile = Join-Path $testProfile 'codex'
        [void](New-Item -ItemType Directory -Path $localProfile,$codexProfile -Force)
        $startInfo.Environment['LOCALAPPDATA'] = $localProfile
        $startInfo.Environment['CODEX_HOME'] = $codexProfile
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::new()
        try {
            $process.StartInfo = $startInfo
            if (-not $process.Start()) { throw "Could not start $($test.Name)" }
            # Read both streams concurrently; a chatty child cannot deadlock.
            $outputRead = $process.StandardOutput.ReadToEndAsync()
            $errorRead = $process.StandardError.ReadToEndAsync()
            $timedOut = -not $process.WaitForExit($TestTimeoutSeconds * 1000)
            if ($timedOut) {
                $stderr += "TIMEOUT — exceeded $TestTimeoutSeconds seconds; terminating process tree." + [Environment]::NewLine
                try { $process.Kill($true) }
                catch { $stderr += "Termination failed: $($_.Exception.Message)" + [Environment]::NewLine }
                [void]$process.WaitForExit(5000)
            }
            if ($process.HasExited) { $code = if ($timedOut) { 124 } else { [int]$process.ExitCode } }
            if ($outputRead.Wait(5000)) { $stdout = $outputRead.GetAwaiter().GetResult() }
            else { $code = 1; $stderr += "Output pipe did not close." + [Environment]::NewLine }
            if ($errorRead.Wait(5000)) { $stderr += $errorRead.GetAwaiter().GetResult() }
            else { $code = 1; $stderr += "Error pipe did not close." + [Environment]::NewLine }
        } catch {
            $code = 1
            $stderr += "ACCEPTANCE ERROR — $($_.Exception.Message)" + [Environment]::NewLine
        } finally {
            $process.Dispose()
        }
        [IO.File]::WriteAllText($log, ($stdout + [Environment]::NewLine + $stderr))
        $results.Add([pscustomobject]@{Name=$test.Name;Exit=$code;Log=$log})
        Write-Host "$(if($code -eq 0){'PASS'}else{'FAIL'}) — $($test.Name)" -ForegroundColor $(if($code -eq 0){'Green'}else{'Red'})
    }
    $postTests = @(& git -C $root status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0 -or ($ExpectedCommit -and $postTests.Count -gt 0)) {
        throw "SOURCE INTEGRITY FAILURE during tests: $($postTests -join '; ')"
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
    try { Set-Location -LiteralPath $originalDirectory } catch { }
    Write-Host 'Continuum — Windows acceptance end' -ForegroundColor Magenta
}
