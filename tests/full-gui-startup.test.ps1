# Start the complete production entrypoint rather than an isolated dashboard mock.
# A responsive native Forms window must exist, not merely a live PowerShell process.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'CodexResumeScheduler.ps1'
$start = [System.Diagnostics.ProcessStartInfo]::new()
$start.FileName = (Get-Command pwsh.exe -ErrorAction Stop).Source
$start.WorkingDirectory = $root
foreach ($arg in @('-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$app)) { [void]$start.ArgumentList.Add($arg) }
$start.UseShellExecute = $false
$start.RedirectStandardError = $true
$start.RedirectStandardOutput = $true
$start.CreateNoWindow = $true
# Isolate test preferences and collect the actual GUI startup log.
$testProfile=Join-Path ([IO.Path]::GetTempPath()) ('scheduler-startup-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testProfile -Force)
$start.Environment['LOCALAPPDATA']=$testProfile
$startupLog=Join-Path $testProfile 'CodexResumeScheduler\gui-startup.log'
$p = [System.Diagnostics.Process]::new()
$p.StartInfo = $start
try {
    if (-not $p.Start()) { throw 'PowerShell GUI host did not start.' }
    $title = ''
    for ($i=0; $i -lt 90; $i++) {
        $p.Refresh()
        if ($p.HasExited) { break }
        $title = [string]$p.MainWindowTitle
        if ($title -match 'Codex Resume Scheduler v|Scheduler startup error') { break }
        Start-Sleep -Milliseconds 150
    }
    $p.Refresh()
    if ($title -notmatch 'Codex Resume Scheduler v') {
        $info = if ($p.HasExited) { "exit=$($p.ExitCode)" } else { 'process alive but no GUI window' }
        if (-not $p.HasExited) { try { $p.Kill($true); $p.WaitForExit(4000) | Out-Null } catch {} }
        $errors = $p.StandardError.ReadToEnd()
        $output = $p.StandardOutput.ReadToEnd()
        $diagnostic=if(Test-Path -LiteralPath $startupLog){(Get-Content -LiteralPath $startupLog -Tail 3) -join ' | '}else{'No startup log recorded'}
        throw "Full UI failed to open ($info); startup: $diagnostic; stderr: $errors; stdout: $output"
    }
    Write-Host "Full production GUI opened: $title"
} finally {
    if (-not $p.HasExited) { try { $p.Kill($true); $p.WaitForExit(4000) | Out-Null } catch {} }
    $p.Dispose()
    if(Test-Path -LiteralPath $testProfile){Remove-Item -LiteralPath $testProfile -Recurse -Force -ErrorAction SilentlyContinue}
}
