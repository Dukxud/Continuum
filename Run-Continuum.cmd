@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "CONTINUUM_BOOTSTRAP=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%CONTINUUM_BOOTSTRAP%" (
  echo Windows PowerShell bootstrap is unavailable at "%CONTINUUM_BOOTSTRAP%".
  echo Restore that Windows component, or open Run-Continuum.ps1 from PowerShell 7.
  pause
  exit /b 1
)
set "CONTINUUM_LAUNCHER=%~dp0Run-Continuum.ps1"
echo Continuum: checking this folder for the current source or a complete application package.
echo Continuum: trusting this local launcher file only; no system execution-policy changes.
"%CONTINUUM_BOOTSTRAP%" -NoLogo -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop'; function Get-ContinuumPowerShellCandidates { param([string]$SearchPath,[string[]]$FallbackRoots) $directories=@($SearchPath -split ';'); foreach($base in $FallbackRoots){if($base){$directories+=($base.TrimEnd([char]92,[char]47)+'\PowerShell\7')}}; foreach($directory in $directories){$directory=$directory.Trim(); if($directory.Length -ge 2 -and $directory[0] -eq [char]34 -and $directory[$directory.Length-1] -eq [char]34){$directory=$directory.Substring(1,$directory.Length-2)}; if($directory -match '^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+)'){$directory.TrimEnd([char]92,[char]47)+'\pwsh.exe'}} }; $selected=Get-ContinuumPowerShellCandidates -SearchPath $env:PATH -FallbackRoots @($env:ProgramW6432,$env:ProgramFiles) | Where-Object {[IO.File]::Exists($_)} | Select-Object -First 1; if(-not $selected){throw 'Continuum requires PowerShell 7.4 or newer in an absolute PATH directory or Program Files. Install x64 PowerShell 7, then reopen this launcher.'}; Write-Host ('PowerShell host: '+$selected); Unblock-File -LiteralPath $env:CONTINUUM_LAUNCHER -ErrorAction Stop; & $selected -NoLogo -NoProfile -STA -File $env:CONTINUUM_LAUNCHER; exit $LASTEXITCODE"
set "CONTINUUM_EXIT=%ERRORLEVEL%"
if not "%CONTINUUM_EXIT%"=="0" (
  echo Continuum failed to launch. Review the error above.
  pause
  exit /b %CONTINUUM_EXIT%
)
exit /b 0
