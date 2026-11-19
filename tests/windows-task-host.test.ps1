# Exercise the production WScript wrapper with a harmless local worker.
# No task is registered, no Codex process runs, and no account data is read.
$ErrorActionPreference='Stop'
if(-not $IsWindows){Write-Host 'SKIP native Windows Script Host integration requires Windows.';return}
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/backend/CodexRunEngine.ps1')
$wscript=Join-Path $env:WINDIR 'System32/wscript.exe'
if(-not (Test-Path -LiteralPath $wscript -PathType Leaf)){
    throw 'Windows Script Host is missing. Continuum scheduled jobs require the Windows VBScript optional feature.'
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum-task-host-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixture)
try{
    $runner=Join-Path $fixture 'CodexRunJob.vbs'
    Copy-Item -LiteralPath (Join-Path $root 'src/backend/CodexRunJob.vbs') -Destination $runner
    $job=Join-Path $fixture 'job with spaces.json'
    '{}' | Set-Content -LiteralPath $job -Encoding utf8
    @'
param([string]$JobFile)
[pscustomobject]@{job=$JobFile;host=(Join-Path $PSHOME 'pwsh.exe')} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'observed.json') -Encoding utf8
exit 17
'@ | Set-Content -LiteralPath (Join-Path $fixture 'Invoke-CodexJob.ps1') -Encoding utf8
    function Run-Probe([string]$Arguments){
        $info=[Diagnostics.ProcessStartInfo]::new($wscript,$Arguments)
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.WorkingDirectory=$fixture
        # A portable installation must work without a parallel MSI install.
        $info.Environment['ProgramFiles']=Join-Path $fixture 'absent Program Files'
        $process=[Diagnostics.Process]::Start($info)
        try{
            if(-not $process.WaitForExit(15000)){
                $process.Kill($true)
                throw 'Windows Script Host did not finish the harmless launch probe. Check whether the Windows VBScript optional feature or organizational policy blocks it.'
            }
            return $process.ExitCode
        }finally{$process.Dispose()}
    }
    $arguments=Get-CodexTaskArguments -Runner $runner -JobFile $job
    $exitCode=Run-Probe $arguments
    $observed=Join-Path $fixture 'observed.json'
    if($exitCode -ne 17 -or -not (Test-Path -LiteralPath $observed)){
        throw "Windows Script Host could not launch the selected PowerShell host (exit $exitCode). Enable the Windows VBScript optional feature if it is missing; do not run Continuum elevated."
    }
    $result=Get-Content -LiteralPath $observed -Raw | ConvertFrom-Json
    if($result.job -cne $job -or $result.host -ine (Get-CodexPowerShellExecutable)){
        throw 'The scheduled launcher changed the verified job or PowerShell host.'
    }
    Remove-Item -LiteralPath $observed
    [IO.File]::WriteAllText((Join-Path $fixture 'pwsh.exe'),'cwd decoy; never execute')
    $unsafe='//B //Nologo "'+$runner+'" "'+$job+'" "pwsh.exe"'
    if((Run-Probe $unsafe) -ne 2 -or (Test-Path -LiteralPath $observed)){
        throw 'The scheduled launcher accepted an unqualified PowerShell executable.'
    }
    Write-Host 'Windows worker launcher pins its current PowerShell, preserves exit status and rejects CWD fallback PASS.'
}finally{Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
