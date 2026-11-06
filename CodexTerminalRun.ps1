# Run the npm Codex TUI with genuine console stdin/stdout/stderr.
# No shell interpolation and no PowerShell pipeline: prompts and approvals
# remain interactive, and the child process exit code is authoritative.
function Invoke-CodexTerminal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CliEntry,
          [Parameter(Mandatory)][string[]]$Arguments)

    $node=(Get-Command node.exe -ErrorAction Stop).Source
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$node
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$false
    [void]$start.ArgumentList.Add($CliEntry)
    foreach($arg in $Arguments){[void]$start.ArgumentList.Add($arg)}

    $process=[Diagnostics.Process]::Start($start)
    if(-not $process){throw 'Unable to start the interactive Codex process.'}
    try{
        $process.WaitForExit()
        return [int]$process.ExitCode
    }finally{
        $process.Dispose()
    }
}
