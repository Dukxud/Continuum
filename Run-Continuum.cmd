@echo off
setlocal
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo Continuum requires PowerShell 7. Install it and try again.
  pause
  exit /b 1
)
set "CONTINUUM_LAUNCHER=%~dp0Run-Continuum.ps1"
echo Continuum: trusting this local launcher file only; no system execution-policy changes.
pwsh.exe -NoLogo -NoProfile -STA -Command "Unblock-File -LiteralPath $env:CONTINUUM_LAUNCHER -ErrorAction Stop; & $env:CONTINUUM_LAUNCHER"
if errorlevel 1 (
  echo Continuum failed to launch. Review the error above.
  pause
  exit /b 1
)
