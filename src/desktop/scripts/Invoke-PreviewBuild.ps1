# Windows owns the wrapper and all ordinary CreateProcess descendants in one
# noninheritable job. Linux tests use a private session/process group. Neither
# path searches for or terminates unrelated processes by name or a stale PID.
function Initialize-ContinuumBuildOwnership {
    if('Continuum.BuildChildOwnership' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Continuum {
    public static class BuildChildOwnership {
        [StructLayout(LayoutKind.Sequential)]
        private struct BasicLimits {
            public long ProcessTime, JobTime;
            public uint Flags;
            public UIntPtr MinimumWorkingSet, MaximumWorkingSet;
            public uint ActiveProcesses;
            public UIntPtr Affinity;
            public uint Priority, Scheduling;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct IoCounters {
            public ulong ReadOperations, WriteOperations, OtherOperations;
            public ulong ReadBytes, WriteBytes, OtherBytes;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ExtendedLimits {
            public BasicLimits Basic;
            public IoCounters Io;
            public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
        private static extern SafeFileHandle CreateJobObjectW(IntPtr attributes, string name);
        [DllImport("kernel32.dll", ExactSpelling=true, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(SafeFileHandle job, int kind, ref ExtendedLimits limits, uint size);
        [DllImport("kernel32.dll", ExactSpelling=true, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);
        [DllImport("libc", SetLastError=true)]
        private static extern int getpgid(int pid);
        [DllImport("libc", SetLastError=true)]
        private static extern int kill(int pid, int signal);

        public static SafeFileHandle OwnWindowsProcess(Process process) {
            // Null SECURITY_ATTRIBUTES makes this handle noninheritable.
            // KILL_ON_JOB_CLOSE is specified with ExtendedLimitInformation (9).
            // https://learn.microsoft.com/windows/win32/procthread/job-objects
            var job=CreateJobObjectW(IntPtr.Zero, null);
            if(job.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot create the build process job.");
            try {
                var limits=new ExtendedLimits();
                limits.Basic.Flags=0x2000;
                if(!SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf<ExtendedLimits>()))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot configure the build process job.");
                if(!AssignProcessToJobObject(job, process.Handle))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot contain the build process. No build tool was started.");
                return job;
            } catch {job.Dispose(); throw;}
        }
        public static bool IsPrivateUnixGroup(Process process) {
            return !process.HasExited && getpgid(process.Id)==process.Id;
        }
        public static void StopUnixGroup(Process process) {
            // The gated wrapper stays alive until this call. Do not signal a
            // potentially reused group number after an unexpected owner exit.
            if(!IsPrivateUnixGroup(process))
                throw new InvalidOperationException("Build process ownership was lost; refusing to signal a stale process group.");
            if(kill(-process.Id, 9)!=0)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot stop the owned build process group.");
        }
    }
}
'@
}

# Run build tools with one deadline and a 16 MiB raw-output limit. A controlled
# wrapper waits for ownership before it starts the tool, and stays alive after
# the tool exits so descendants retaining pipes can always be cleaned up.
function Invoke-ContinuumBuildProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList=@(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [ValidateRange(1,7200)][int]$TimeoutSeconds=120,
        [switch]$StreamOutput
    )
    if($PSVersionTable.PSVersion -lt [version]'7.4'){
        throw 'Continuum source builds require PowerShell 7.4 or newer.'
    }
    if(-not [IO.Path]::IsPathFullyQualified($FilePath) -or
       -not (Test-Path -LiteralPath $FilePath -PathType Leaf)){
        throw "Build tool executable is missing or is not an absolute path: $FilePath"
    }
    Initialize-ContinuumBuildOwnership
    $powerShell=Join-Path $PSHOME ($IsWindows ? 'pwsh.exe' : 'pwsh')
    $toolExecutable=$FilePath
    $toolArguments=$ArgumentList
    if([IO.Path]::GetExtension($FilePath) -in @('.bat','.cmd')){
        # PowerShell's native-command binder handles Windows batch entrypoints.
        # Encode literal arguments rather than interpolating a cmd.exe command.
        if(-not $IsWindows){throw 'Windows batch build tools require Windows.'}
        $toolExecutable=$powerShell
        $literals=@($FilePath)+$ArgumentList | ForEach-Object {"'"+$_.Replace("'","''")+"'"}
        $command='$ErrorActionPreference=''Stop''; try { & '+($literals -join ' ')+
            '; exit $LASTEXITCODE } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }'
        $toolArguments=@('-NoLogo','-NoProfile','-NonInteractive','-OutputFormat','Text','-EncodedCommand',
            [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
    }
    $controlDirectory=Join-Path ([IO.Path]::GetTempPath()) ('continuum-build-owner-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($controlDirectory)
    $statusPath=Join-Path $controlDirectory 'exit.status'
    $wrapper=@'
$ErrorActionPreference='Stop'
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$request=$null;$child=$null;$code=1
try{
    $request=[Console]::In.ReadLine() | ConvertFrom-Json -ErrorAction Stop
    if(-not $request){throw 'Build owner received no launch request.'}
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
'@
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$powerShell
    if(-not $IsWindows){
        $setsid=Get-Command setsid -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if(-not $setsid){Remove-Item -LiteralPath $controlDirectory -Force;throw 'Portable build-process tests require setsid for process ownership.'}
        $info.FileName=$setsid.Source
        $info.ArgumentList.Add($powerShell)
    }
    foreach($arg in @('-NoLogo','-NoProfile','-NonInteractive','-OutputFormat','Text','-EncodedCommand',
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapper)))){
        $info.ArgumentList.Add($arg)
    }
    $info.WorkingDirectory=[IO.Path]::GetFullPath($WorkingDirectory)
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true
    $info.RedirectStandardError=$true
    $info.RedirectStandardInput=$true
    $info.StandardInputEncoding=[Text.UTF8Encoding]::new($false)
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$info
    $started=$false;$job=$null;$ownedGroup=$false;$stopped=$false
    $toolExitCode=$null
    $stdout=[Text.StringBuilder]::new()
    $stderr=[Text.StringBuilder]::new()
    $readers=@(
        @{Buffer=[byte[]]::new(8192);Chars=[char[]]::new(8193);Decoder=[Text.UTF8Encoding]::new($false).GetDecoder();Text=$stdout;Task=$null;Stream=$null},
        @{Buffer=[byte[]]::new(8192);Chars=[char[]]::new(8193);Decoder=[Text.UTF8Encoding]::new($false).GetDecoder();Text=$stderr;Task=$null;Stream=$null}
    )
    $outputBytes=0L
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try{
        $started=$process.Start()
        if(-not $started){throw "Could not start build tool: $FilePath"}
        if($IsWindows){$job=[Continuum.BuildChildOwnership]::OwnWindowsProcess($process)}
        else{
            while(-not [Continuum.BuildChildOwnership]::IsPrivateUnixGroup($process)){
                if($process.HasExited){throw 'Build process owner exited before establishing its private group.'}
                if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){throw "Build tool timed out after $TimeoutSeconds seconds: $FilePath"}
                [Threading.Thread]::Sleep(5)
            }
            $ownedGroup=$true
        }
        $request=@{executable=$toolExecutable;arguments=@($toolArguments);directory=$info.WorkingDirectory;status=$statusPath} | ConvertTo-Json -Depth 4 -Compress
        $process.StandardInput.WriteLine($request)
        $process.StandardInput.Flush()
        $readers[0].Stream=$process.StandardOutput.BaseStream
        $readers[1].Stream=$process.StandardError.BaseStream
        foreach($reader in $readers){$reader.Task=$reader.Stream.ReadAsync($reader.Buffer,0,$reader.Buffer.Length)}
        $exitTask=$process.WaitForExitAsync()
        while($true){
            foreach($reader in $readers){
                if($null -ne $reader.Task -and $reader.Task.IsCompleted){
                    $size=$reader.Task.GetAwaiter().GetResult()
                    $outputBytes+=$size
                    if($outputBytes -gt 16MB){throw "Build tool output exceeded its 16 MiB limit: $FilePath"}
                    $characters=$reader.Decoder.GetChars($reader.Buffer,0,$size,$reader.Chars,0,($size -eq 0))
                    if($characters){
                        $text=[string]::new($reader.Chars,0,$characters)
                        if($reader.Text.Length -eq 0 -and $text[0] -eq [char]0xFEFF){$text=$text.Substring(1)}
                        [void]$reader.Text.Append($text)
                        if($StreamOutput){Write-Host -NoNewline $text}
                    }
                    $reader.Task=if($size){$reader.Stream.ReadAsync($reader.Buffer,0,$reader.Buffer.Length)}else{$null}
                }
            }
            if($null -eq $toolExitCode -and [IO.File]::Exists($statusPath)){
                $toolExitCode=[int][IO.File]::ReadAllText($statusPath)
                if($job){$job.Dispose();$job=$null}
                else{[Continuum.BuildChildOwnership]::StopUnixGroup($process);$ownedGroup=$false}
                $stopped=$true
            }
            if($exitTask.IsCompleted -and $null -eq $toolExitCode){throw 'Build process owner exited without reporting the tool result.'}
            if($exitTask.IsCompleted -and @($readers | Where-Object {$null -ne $_.Task}).Count -eq 0){break}
            $remaining=[int]($TimeoutSeconds*1000-$clock.ElapsedMilliseconds)
            if($remaining -le 0){throw "Build tool timed out after $TimeoutSeconds seconds: $FilePath"}
            # Drain ready chunks immediately. Waiting while a replacement read
            # is already complete throttles a chatty compiler to ten lines/sec.
            if(@($readers | Where-Object {$null -ne $_.Task -and $_.Task.IsCompleted}).Count){continue}
            $waiting=[Collections.Generic.List[Threading.Tasks.Task]]::new()
            foreach($task in @($readers[0].Task,$readers[1].Task,$exitTask)){
                if($null -ne $task -and -not $task.IsCompleted){$waiting.Add($task)}
            }
            if($waiting.Count){
                [void][Threading.Tasks.Task]::WaitAny($waiting.ToArray(),[Math]::Min(25,$remaining))
            }
        }
        [void]$exitTask.GetAwaiter().GetResult()
        return [pscustomobject]@{
            ExitCode=$toolExitCode
            Stdout=$stdout.ToString()
            Stderr=$stderr.ToString()
        }
    }finally{
        try{
            if($job){$job.Dispose()}
            elseif($ownedGroup){[Continuum.BuildChildOwnership]::StopUnixGroup($process)}
            elseif($started -and -not $stopped -and -not $process.HasExited){$process.Kill()}
            if($started){[void]$process.WaitForExit(2000)}
        }finally{
            $process.Dispose()
            Remove-Item -LiteralPath $controlDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ContinuumBuildStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList=@(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [ValidateRange(1,7200)][int]$TimeoutSeconds=120
    )
    Write-Host "Continuum build: $Name"
    try{
        $result=Invoke-ContinuumBuildProcess -FilePath $FilePath -ArgumentList $ArgumentList `
            -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds -StreamOutput
    }catch{throw "${Name}: $($_.Exception.Message)"}
    if($result.ExitCode -ne 0){
        throw "$Name failed (exit $($result.ExitCode)). The tool's error is shown above."
    }
}

# Both source entrypoints validate the same candidate, independent of an
# inherited override that may point at a previously installed application.
function Invoke-ContinuumPreviewBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][object]$Tools,
        [switch]$BuildRelease
    )
    $project=[IO.Path]::GetFullPath($ProjectDirectory)
    $root=[IO.Path]::GetFullPath((Join-Path $project '../..'))
    $previousSource=$env:CODEX_SCHEDULER_SOURCE
    $previousPowerShell=$env:CONTINUUM_TEST_PWSH
    try{
        $env:CODEX_SCHEDULER_SOURCE=$root
        $env:CONTINUUM_TEST_PWSH=$Tools.PowerShellExecutable
        Invoke-ContinuumBuildStep -Name 'Source integrity' -FilePath $Tools.PowerShellExecutable `
            -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $root 'tests/flutter-port-source.test.ps1')) `
            -WorkingDirectory $project
        Invoke-ContinuumBuildStep -Name 'Windows bridge integration' -FilePath $Tools.PowerShellExecutable `
            -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-STA','-File',(Join-Path $root 'tests/flutter-port-bridge.test.ps1')) `
            -WorkingDirectory $project -TimeoutSeconds 300
        Invoke-ContinuumBuildStep -Name 'Windows worker launcher integration' -FilePath $Tools.PowerShellExecutable `
            -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $root 'tests/windows-task-host.test.ps1')) `
            -WorkingDirectory $project -TimeoutSeconds 60
        Invoke-ContinuumBuildStep -Name 'Windows runner generation' -FilePath $Tools.PowerShellExecutable `
            -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $project 'scripts/Initialize-WindowsRunner.ps1'),'-FlutterExecutable',$Tools.FlutterExecutable) `
            -WorkingDirectory $project -TimeoutSeconds 300
        Invoke-ContinuumBuildStep -Name 'Flutter locked dependencies (pub get --enforce-lockfile)' `
            -FilePath $Tools.FlutterExecutable -ArgumentList @('pub','get','--enforce-lockfile') `
            -WorkingDirectory $project -TimeoutSeconds 600
        Invoke-ContinuumBuildStep -Name 'Dart analysis' -FilePath $Tools.FlutterExecutable `
            -ArgumentList @('analyze','--no-pub') -WorkingDirectory $project -TimeoutSeconds 300
        Invoke-ContinuumBuildStep -Name 'Flutter regression tests' -FilePath $Tools.FlutterExecutable `
            -ArgumentList @('test','--no-pub','--exclude-tags','visual-capture') `
            -WorkingDirectory $project -TimeoutSeconds 600
        if($BuildRelease){
            Invoke-ContinuumBuildStep -Name 'Windows release compilation' -FilePath $Tools.FlutterExecutable `
                -ArgumentList @('build','windows','--release','--no-pub') `
                -WorkingDirectory $project -TimeoutSeconds 1800
        }
    }finally{
        $env:CODEX_SCHEDULER_SOURCE=$previousSource
        $env:CONTINUUM_TEST_PWSH=$previousPowerShell
    }
}
