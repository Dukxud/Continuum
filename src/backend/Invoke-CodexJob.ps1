# Scheduled worker entry point. Independent of the legacy Windows Forms UI.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$JobFile)

$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($JobFile) -or -not [IO.Path]::IsPathFullyQualified($JobFile)) {
        throw 'Scheduled job file path must be absolute.'
    }
    . (Join-Path $PSScriptRoot 'CodexRunEngine.ps1')
    $runtimeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $jobDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($JobFile))
    exit (Invoke-CodexScheduledJob -JobFile $JobFile -AppDirectory $jobDirectory -RuntimeDirectory $runtimeRoot)
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
