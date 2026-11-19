# Actual child processes exercise the common build boundary on every host.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/desktop/scripts/Invoke-PreviewBuild.ps1')
$pwsh=Join-Path $PSHOME ($IsWindows ? 'pwsh.exe' : 'pwsh')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum-build-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixture)
$count=0
function Check([string]$Name,[scriptblock]$Body){& $Body;$script:count++;Write-Host "PASS $Name"}
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
try{
    Check 'owned process host uses an auditable script file rather than an encoded command' {
        $implementation=[IO.File]::ReadAllText((Join-Path $root 'src/desktop/scripts/Invoke-PreviewBuild.ps1'))
        Assert-That ($implementation.Contains("'owner.ps1'") -and
            $implementation.Contains("'-File',"+'$ownerScript') -and
            -not $implementation.Contains('-EncodedCommand')) 'Build process host still uses an opaque command.'
    }
    if($IsWindows){
        Check 'actual Windows batch file runs inside the owned host with its exit code' {
            $batch=Join-Path $fixture 'batch tool with spaces.cmd'
            [IO.File]::WriteAllText($batch,("@echo off"+[Environment]::NewLine+
                "echo BATCH-CHECK"+[Environment]::NewLine+"exit /b 29"+[Environment]::NewLine))
            $run=Invoke-ContinuumBuildProcess -FilePath $batch -ArgumentList @() -WorkingDirectory $fixture
            Assert-That ($run.ExitCode -eq 29 -and $run.Stdout.Contains('BATCH-CHECK')) 'Batch tool result was lost.'
        }
    }
    $child=Join-Path $fixture 'tool with spaces.ps1'
    @'
param([string]$Value,[int]$ExitCode=0,[int]$Delay=0)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::Out.WriteLine((@{value=$Value;directory=$PWD.Path} | ConvertTo-Json -Compress))
[Console]::Error.WriteLine('tool diagnostic élan')
if($Delay){Start-Sleep -Seconds $Delay}
exit $ExitCode
'@ | Set-Content -LiteralPath $child -Encoding utf8
    Check 'real executable preserves Unicode, quotes, shell characters, CWD and separate stderr' {
        $value='élan 仓库 & $() ; ''quoted'' "double" trailing\'
        $result=Invoke-ContinuumBuildProcess -FilePath $pwsh -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$child,'-Value',$value) -WorkingDirectory $fixture
        Assert-That ($result -isnot [array]) 'Completion emitted an extra success-stream object.'
        Assert-That ($result.ExitCode -eq 0) 'Child failed.'
        $body=$result.Stdout | ConvertFrom-Json
        Assert-That ($body.value -ceq $value) 'Literal arguments changed.'
        Assert-That ($body.directory -ceq $fixture) 'Working directory changed.'
        Assert-That ($result.Stderr.Contains('tool diagnostic élan')) 'Stderr was lost or mixed into stdout.'
    }
    Check 'a real nonzero command retains its exit code' {
        $result=Invoke-ContinuumBuildProcess -FilePath $pwsh -ArgumentList @('-NoProfile','-File',$child,'-ExitCode','37') -WorkingDirectory $fixture
        Assert-That ($result.ExitCode -eq 37) 'Nonzero exit was lost.'
    }
    Check 'a UTF-8 BOM is removed before parsing a tool JSON response' {
        $code=@'
$output=[Console]::OpenStandardOutput()
$bytes=[byte[]]@(239,187,191)+[Text.Encoding]::UTF8.GetBytes('{"ready":true}')
$output.Write($bytes,0,$bytes.Length);$output.Flush()
'@
        $result=Invoke-ContinuumBuildProcess -FilePath $pwsh -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-Command',$code) -WorkingDirectory $fixture
        Assert-That ($result.Stdout -ceq '{"ready":true}') 'BOM leaked into the JSON contract.'
    }
    Check 'stage failure identifies the stage and stops the caller' {
        $continued=$false;$failure=''
        try{
            Invoke-ContinuumBuildStep -Name 'Locked dependencies' -FilePath $pwsh -ArgumentList @('-NoProfile','-File',$child,'-ExitCode','37') -WorkingDirectory $fixture
            $continued=$true
        }catch{$failure=$_.Exception.Message}
        Assert-That (-not $continued -and $failure.Contains('Locked dependencies') -and $failure.Contains('37')) 'Stage failure was hidden.'
    }
    Check 'a hanging real tool has a bounded failure' {
        $watch=[Diagnostics.Stopwatch]::StartNew();$failure=''
        try{Invoke-ContinuumBuildProcess -FilePath $pwsh -ArgumentList @('-NoProfile','-File',$child,'-Delay','30') -WorkingDirectory $fixture -TimeoutSeconds 1 | Out-Null}
        catch{$failure=$_.Exception.Message}
        Assert-That ($failure.Contains('timed out') -and $watch.Elapsed.TotalSeconds -lt 5) 'Hung command was not bounded.'
    }
    Check 'missing and relative executables fail before invocation' {
        foreach($path in @('pwsh', (Join-Path $fixture 'missing.exe'))){
            $failed=$false
            try{Invoke-ContinuumBuildProcess -FilePath $path -WorkingDirectory $fixture | Out-Null}catch{$failed=$true}
            Assert-That $failed 'Invalid executable was accepted.'
        }
    }
    Check 'large buffered output drains without line-by-line throttling or UTF-8 loss' {
        $code=@'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::Out.Write(('élan 仓库' * 100000))
[Console]::Error.Write(('diagnostic' + [char]10) * 100000)
'@
        $result=Invoke-ContinuumBuildProcess -FilePath $pwsh -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-Command',$code) -WorkingDirectory $fixture -TimeoutSeconds 6
        Assert-That ($result.ExitCode -eq 0) 'Buffered output caused a false tool failure.'
        Assert-That ($result.Stdout -ceq ('élan 仓库' * 100000)) 'Chunked stdout lost or corrupted Unicode.'
        Assert-That ($result.Stderr -ceq (('diagnostic'+[char]10)*100000)) 'Buffered stderr was lost or mixed into stdout.'
    }
    foreach($stream in @('Out','Error')){
        Check "unterminated oversized $stream is bounded before the command timeout" {
            $code="[Console]::$stream.Write(('x' * (17MB))); [Console]::$stream.Flush(); [Threading.Thread]::Sleep(30000)"
            $failure=''
            try{Invoke-ContinuumBuildProcess -FilePath $pwsh -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-Command',$code) -WorkingDirectory $fixture -TimeoutSeconds 6 | Out-Null}
            catch{$failure=$_.Exception.Message}
            Assert-That ($failure.Contains('output exceeded its 16 MiB limit')) "Unterminated output escaped its size limit: $failure"
        }
    }

    $heartbeatChild=Join-Path $fixture 'heartbeat.ps1'
    @'
param([string]$Heartbeat,[string]$Identity)
$self=Get-Process -Id $PID
@{id=$PID;started=$self.StartTime.ToUniversalTime().Ticks} | ConvertTo-Json -Compress |
    Set-Content -LiteralPath $Identity -Encoding utf8
while($true){[IO.File]::WriteAllText($Heartbeat,[string][DateTimeOffset]::UtcNow.Ticks);[Threading.Thread]::Sleep(25)}
'@ | Set-Content -LiteralPath $heartbeatChild -Encoding utf8
    $earlyWrapper=Join-Path $fixture 'early-wrapper.ps1'
    @'
param([string]$PowerShell,[string]$ChildScript,[string]$Heartbeat,[string]$Identity,[switch]$Hold)
$start=[Diagnostics.ProcessStartInfo]::new()
$start.FileName=$PowerShell;$start.UseShellExecute=$false;$start.RedirectStandardInput=$true
foreach($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',$ChildScript,'-Heartbeat',$Heartbeat,'-Identity',$Identity)){$start.ArgumentList.Add($arg)}
$child=[Diagnostics.Process]::Start($start)
$child.StandardInput.Close()
$watch=[Diagnostics.Stopwatch]::StartNew()
while(-not [IO.File]::Exists($Heartbeat)){
    if($child.HasExited -or $watch.Elapsed.TotalSeconds -ge 5){throw 'Heartbeat child failed to initialize.'}
    [Threading.Thread]::Sleep(10)
}
[Console]::Out.WriteLine('target wrapper is ready')
if($Hold){[Threading.Thread]::Sleep(30000)}
exit 0
'@ | Set-Content -LiteralPath $earlyWrapper -Encoding utf8
    foreach($hold in @($false,$true)){
        $caseName=if($hold){'timeout stops an active tool and its descendant heartbeat'}else{'exited target wrapper cannot leave a live descendant holding output pipes'}
        Check $caseName {
            $heartbeat=Join-Path $fixture ('heartbeat-'+$hold+'.txt')
            $identity=Join-Path $fixture ('child-'+$hold+'.json')
            try{
                $testArguments=@('-NoLogo','-NoProfile','-NonInteractive','-File',$earlyWrapper,'-PowerShell',$pwsh,'-ChildScript',$heartbeatChild,'-Heartbeat',$heartbeat,'-Identity',$identity)
                if($hold){$testArguments+='-Hold'}
                $failure='';$result=$null
                try{$result=Invoke-ContinuumBuildProcess -FilePath $pwsh -ArgumentList $testArguments -WorkingDirectory $fixture -TimeoutSeconds 4}
                catch{$failure=$_.Exception.Message}
                Assert-That ([IO.File]::Exists($heartbeat)) 'A descendant never started; this did not test tree cleanup.'
                if($hold){Assert-That ($failure.Contains('timed out')) "Expected bounded timeout, received: $failure"}
                else{Assert-That ($failure -eq '' -and $result.ExitCode -eq 0 -and $result.Stdout.Contains('target wrapper is ready')) "Exited wrapper did not complete: $failure"}
                $before=[IO.File]::ReadAllText($heartbeat)
                [Threading.Thread]::Sleep(150)
                Assert-That ([IO.File]::ReadAllText($heartbeat) -ceq $before) 'A descendant continued running after process completion.'
            }finally{
                # Only clean up this fixture's recorded process if a regression
                # leaves it alive; matching creation time avoids stale PID reuse.
                if(Test-Path -LiteralPath $identity){
                    $owned=Get-Content -LiteralPath $identity -Raw | ConvertFrom-Json
                    $orphan=Get-Process -Id ([int]$owned.id) -ErrorAction SilentlyContinue
                    if($orphan -and -not $orphan.HasExited -and $orphan.StartTime.ToUniversalTime().Ticks -eq [long]$owned.started){
                        $orphan.Kill($true);[void]$orphan.WaitForExit(2000);$orphan.Dispose()
                    }
                }
            }
        }
    }

    # Use the actual orchestration function, with stage execution recorded at
    # its process boundary. The real process behavior is exercised above.
    $script:steps=[Collections.Generic.List[object]]::new()
    $script:failStage=''
    function Invoke-ContinuumBuildStep {
        param($Name,$FilePath,$ArgumentList,$WorkingDirectory,$TimeoutSeconds)
        $script:steps.Add([pscustomobject]@{Name=$Name;Executable=$FilePath;Arguments=$ArgumentList;Directory=$WorkingDirectory;Source=$env:CODEX_SCHEDULER_SOURCE;PowerShell=$env:CONTINUUM_TEST_PWSH})
        if($Name -eq $script:failStage){throw 'Injected process failure'}
    }
    $project=Join-Path $fixture 'candidate/src/desktop'
    [void](New-Item -ItemType Directory -Path $project -Force)
    $tools=[pscustomobject]@{PowerShellExecutable=$pwsh;FlutterExecutable=(Join-Path $fixture 'selected Flutter/flutter.bat')}
    $savedSource=$env:CODEX_SCHEDULER_SOURCE;$savedPowerShell=$env:CONTINUUM_TEST_PWSH
    try{
        $env:CODEX_SCHEDULER_SOURCE=Join-Path $fixture 'old installed app'
        $env:CONTINUUM_TEST_PWSH=Join-Path $fixture 'old PowerShell'
        Check 'every stage tests this source and selected SDK, then restores inherited overrides' {
            Invoke-ContinuumPreviewBuild -ProjectDirectory $project -Tools $tools -BuildRelease
            Assert-That ($script:steps.Count -eq 8) 'Build stages missing or duplicated.'
            foreach($step in $script:steps){
                Assert-That ($step.Source -eq (Join-Path $fixture 'candidate')) 'A stage tested an unrelated backend.'
                Assert-That ($step.PowerShell -eq $pwsh -and $step.Directory -eq $project) 'Stage runtime or CWD drifted.'
            }
            Assert-That (($script:steps | Where-Object Name -eq 'Windows runner generation').Arguments[-1] -eq $tools.FlutterExecutable) 'Runner generation can select a different SDK.'
            Assert-That (($script:steps | Where-Object Name -like 'Flutter locked dependencies*').Arguments -contains '--enforce-lockfile') 'Dependency lock is not enforced.'
            Assert-That (($script:steps | Where-Object Name -eq 'Windows worker launcher integration').Arguments[-1] -eq (Join-Path $fixture 'candidate/tests/windows-task-host.test.ps1')) 'Native worker launcher was not checked before compilation.'
            Assert-That ($env:CODEX_SCHEDULER_SOURCE -eq (Join-Path $fixture 'old installed app')) 'Source override was not restored.'
            Assert-That ($env:CONTINUUM_TEST_PWSH -eq (Join-Path $fixture 'old PowerShell')) 'PowerShell override was not restored.'
        }
        Check 'each failed stage prevents all later work and restores both overrides' {
            $names=@($script:steps | ForEach-Object {$_.Name})
            for($index=0;$index -lt $names.Count;$index++){
                $script:steps.Clear();$script:failStage=$names[$index];$failed=$false
                try{Invoke-ContinuumPreviewBuild -ProjectDirectory $project -Tools $tools -BuildRelease}catch{$failed=$true}
                Assert-That ($failed -and $script:steps.Count -eq $index+1) "Work continued after $($names[$index])."
                Assert-That ($env:CODEX_SCHEDULER_SOURCE -eq (Join-Path $fixture 'old installed app')) 'Failure leaked candidate source into caller.'
                Assert-That ($env:CONTINUUM_TEST_PWSH -eq (Join-Path $fixture 'old PowerShell')) 'Failure leaked a test executable override.'
            }
        }
        Check 'review validation omits release compilation' {
            $script:steps.Clear();$script:failStage=''
            Invoke-ContinuumPreviewBuild -ProjectDirectory $project -Tools $tools
            Assert-That ($script:steps.Count -eq 7 -and $script:steps[-1].Name -eq 'Flutter regression tests') 'Review unexpectedly compiled or skipped tests.'
        }
    }finally{
        $env:CODEX_SCHEDULER_SOURCE=$savedSource
        $env:CONTINUUM_TEST_PWSH=$savedPowerShell
    }
    Write-Host "Build process and stage flow: $count passed."
}finally{Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
