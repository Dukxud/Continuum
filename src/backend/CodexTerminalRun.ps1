# Run the installed Codex TUI with genuine console stdin/stdout/stderr.
# No shell interpolation and no PowerShell pipeline: prompts and approvals
# remain interactive, and the child process exit code is authoritative.
function Invoke-CodexTerminal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CliEntry,
          [Parameter(Mandatory)][string[]]$Arguments)

    $start=[Diagnostics.ProcessStartInfo]::new()
    $javascript=[IO.Path]::GetExtension($CliEntry) -ieq '.js'
    $start.FileName=if($javascript){(Get-Command node.exe -ErrorAction Stop).Source}else{$CliEntry}
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$false
    if($javascript){[void]$start.ArgumentList.Add($CliEntry)}
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
