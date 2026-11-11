# Exercise the shipped double-click VBS launcher and locate a visible GUI window.
# A running pwsh process is NOT sufficient; a hidden form caused the v1.10 regression.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'legacy/winforms/Start-Codex-Scheduler.vbs'
$app = Join-Path $root 'legacy/winforms/CodexResumeScheduler.ps1'
$testProfile=Join-Path ([IO.Path]::GetTempPath()) ('scheduler-vbs-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testProfile -Force)
$startupLog=Join-Path $testProfile 'CodexResumeScheduler\gui-startup.log'
$started = @()
try {
    $hostExe = Join-Path $env:WINDIR 'System32\wscript.exe'
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$hostExe
    $start.ArgumentList.Add('//B')
    $start.ArgumentList.Add('//Nologo')
    $start.ArgumentList.Add($launcher)
    $start.WorkingDirectory=$root
    $start.UseShellExecute=$false
    $start.Environment['LOCALAPPDATA']=$testProfile
    $hostProcess=[Diagnostics.Process]::Start($start)
    $launcherProcessId = $hostProcess.Id
    try {
        if (-not $hostProcess.WaitForExit(5000)) { throw 'VBS entrypoint did not return promptly.' }
        if ($hostProcess.ExitCode -ne 0) { throw "VBS entrypoint failed: $($hostProcess.ExitCode)" }
    } finally { $hostProcess.Dispose() }
    $found = $null
    for ($i = 0; $i -lt 80; $i++) {
        $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $launcherProcessId" |
            Where-Object { $_.Name -ieq 'pwsh.exe' -and ([string]$_.CommandLine).Contains($app) })
        $processes = @($children | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
        foreach ($p in $processes) {
            if ($started -notcontains $p.Id) { $started += $p.Id }
            $p.Refresh()
            if ($p.MainWindowTitle -like 'Codex Resume Scheduler v*') { $found = $p; break }
        }
        if ($found) { break }
        Start-Sleep -Milliseconds 150
    }
    if (-not $found) {
        $details = @($started | ForEach-Object {
            try { $p = Get-Process -Id $_ -ErrorAction Stop; "PID $_ title='$($p.MainWindowTitle)'" }
            catch { "PID $_ exited" }
        }) -join '; '
        $diagnostic=if(Test-Path -LiteralPath $startupLog){(Get-Content -LiteralPath $startupLog -Tail 3) -join ' | '}else{'No startup log recorded'}
        throw "Double-click launcher did not display the scheduler window. Startup: $diagnostic. Child processes: $details"
    }
    Write-Host "Visible application window from the real VBS launcher: $($found.MainWindowTitle)"
} finally {
    foreach ($processId in $started) {
        $child = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
        if ($child.ParentProcessId -eq $launcherProcessId -and ([string]$child.CommandLine).Contains($app)) {
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        }
    }
    if(Test-Path -LiteralPath $testProfile){Remove-Item -LiteralPath $testProfile -Recurse -Force -ErrorAction SilentlyContinue}
}
