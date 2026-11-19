# Continuum-owned build subprocess. This static source file is explicitly
# trusted by Run-Continuum.cmd; it never evaluates command-line source text.
$ErrorActionPreference='Stop'
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$request=$null;$child=$null;$code=1
try{
    $request=[Console]::In.ReadLine() | ConvertFrom-Json -ErrorAction Stop
    if(-not $request){throw 'Build owner received no launch request.'}
    if($request.batch -eq $true){
        # PowerShell 7 handles .bat/.cmd argument binding; stdout and stderr
        # flow through this same owner, already assigned to the build job.
        $batchArguments=@($request.arguments | ForEach-Object {[string]$_})
        & ([string]$request.executable) @batchArguments
        if($null -eq $LASTEXITCODE){throw 'Batch tool returned no exit status.'}
        $code=[int]$LASTEXITCODE
    }else{
        $start=[Diagnostics.ProcessStartInfo]::new()
        $start.FileName=[string]$request.executable
        $start.WorkingDirectory=[string]$request.directory
        $start.UseShellExecute=$false
        $start.CreateNoWindow=$true
        $start.RedirectStandardInput=$true
        foreach($argument in $request.arguments){$start.ArgumentList.Add([string]$argument)}
        $child=[Diagnostics.Process]::Start($start)
        $child.StandardInput.Close()
        $child.WaitForExit()
        $code=$child.ExitCode
    }
}catch{[Console]::Error.WriteLine($_.Exception.Message)}
finally{
    if($child){$child.Dispose()}
    try{
        [Console]::Out.Flush();[Console]::Error.Flush()
        if($request){
            [IO.File]::WriteAllText(([string]$request.status+'.tmp'),[string]$code)
            [IO.File]::Move(([string]$request.status+'.tmp'),[string]$request.status)
        }
    }finally{
        # The parent terminates our owned job/group. Keeping the owner alive
        # prevents group/PID reuse while descendants may still hold output.
        [void][Console]::In.ReadLine()
    }
}
