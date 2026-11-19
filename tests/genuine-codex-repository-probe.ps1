# Opt-in local probe against a real, separately installed Codex binary.
# This is intentionally not part of *.test.ps1: the caller supplies the runtime.
# Every Codex process uses a disposable CODEX_HOME, file-only empty credentials,
# and an environment without inherited tokens. No turn, resume, account, or
# scheduling operation is requested. Only Windows task enumeration is stubbed.
param([Parameter(Mandatory)][string]$CodexExecutable)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$powerShell=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$node=(Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$git=(Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
if(-not [IO.Path]::IsPathFullyQualified($CodexExecutable) -or
   -not (Test-Path -LiteralPath $CodexExecutable -PathType Leaf)){
    throw 'Supply an existing absolute path to the genuine native Codex executable.'
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum genuine codex '+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $fixture 'native bin'
$native=Join-Path $bin 'codex.exe'
$codexHome=Join-Path $fixture 'codex home'
$appData=Join-Path $fixture 'appdata'
$outside=Join-Path $fixture 'outside Git'
$repo=Join-Path $fixture 'Horizon checkout'
$sessions=Join-Path $codexHome 'sessions/2026/11/18'
$wrapper=Join-Path $fixture 'invoke-bridge.ps1'
$invocations=Join-Path $fixture 'metadata-requests.jsonl'
$a='0199aaaa-1234-4567-89ab-0000e116d411'
$b='0199bbbb-1234-4567-89ab-0000e116d411'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Normalize([string]$Path){return $Path.Replace('\','/').TrimEnd('/')}
function Invoke-GenuineBridge([string]$Action,$Body=@{}){
    $payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 8 -Compress)))
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$powerShell
    $start.UseShellExecute=$false
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $start.WorkingDirectory=$outside
    foreach($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',$wrapper,$root,$Action,$payload)){
        [void]$start.ArgumentList.Add($arg)
    }
    $start.Environment.Clear()
    # Retain the OS's existing profile location unchanged. PowerShell uses it
    # for ordinary local search roots; CODEX_HOME separately isolates Codex.
    foreach($name in @('SystemRoot','WINDIR','ComSpec','ProgramFiles','HOME','USERPROFILE','HOMEDRIVE','HOMEPATH')){
        $value=[Environment]::GetEnvironmentVariable($name)
        if($value){$start.Environment[$name]=$value}
    }
    $start.Environment['PATH']=$bin+[IO.Path]::PathSeparator+(Split-Path -Parent $git)
    $start.Environment['CODEX_HOME']=$codexHome
    $start.Environment['LOCALAPPDATA']=$appData
    $start.Environment['APPDATA']=$appData
    $start.Environment['TMP']=$fixture
    $start.Environment['TEMP']=$fixture
    $start.Environment['TMPDIR']=$fixture
    $start.Environment['RUST_LOG']='off'
    $start.Environment['CONTINUUM_PROBE_NODE']=$node
    $start.Environment['CONTINUUM_PROBE_NATIVE']=$native
    $start.Environment['CONTINUUM_PROBE_LOG']=$invocations
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$start
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try{
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(45000)){
            $process.Kill($true)
            throw "Genuine Codex bridge $Action exceeded 45 seconds."
        }
        $text=$stdout.GetAwaiter().GetResult()
        $errorText=$stderr.GetAwaiter().GetResult()
        $lines=@($text -split '\r?\n' | Where-Object {$_})
        Require ($lines.Count -eq 1) "Bridge $Action emitted an invalid JSON boundary: $text $errorText"
        $reply=$lines[0] | ConvertFrom-Json -ErrorAction Stop
        Require ($process.ExitCode -eq 0 -and $reply.ok -eq $true) "Bridge $Action failed: $($reply.error) $errorText"
        Write-Host "PASS genuine bridge $Action ($($clock.ElapsedMilliseconds)ms)"
        return $reply.result
    }finally{$process.Dispose()}
}
try{
    [void](New-Item -ItemType Directory -Path $bin,$codexHome,$appData,$outside,$repo,$sessions -Force)
    try{[void](New-Item -ItemType HardLink -Path $native -Target $CodexExecutable -ErrorAction Stop)}
    catch{Copy-Item -LiteralPath $CodexExecutable -Destination $native -ErrorAction Stop}
    @'
cli_auth_credentials_store = "file"
[analytics]
enabled = false
'@ | Set-Content -LiteralPath (Join-Path $codexHome 'config.toml') -Encoding utf8
    & $git init -q -b main $repo
    Require ($LASTEXITCODE -eq 0) 'Could not create the real Git fixture.'
    & $git -C $repo remote add origin https://github.com/fixture/Horizon.git
    Require ($LASTEXITCODE -eq 0) 'Could not set the local Git remote fixture.'
    foreach($entry in @(@{id=$a;cwd=$repo},@{id=$b;cwd=$outside})){
        $timestamp='2026-11-18T15:20:00Z'
        $records=@(
            @{timestamp=$timestamp;type='session_meta';payload=@{
                id=$entry.id;session_id=$entry.id;timestamp=$timestamp;cwd=$entry.cwd
                originator='codex_cli_rs';cli_version='0.170.0';source='cli';model_provider='openai';history_mode='legacy'
                git=@{branch='main';repository_url='https://github.com/fixture/Horizon.git'}}},
            @{timestamp=$timestamp;type='event_msg';payload=@{
                type='user_message';message='Review https://github.com/fixture/Horizon'
                images=@();local_images=@();text_elements=@()}}
        )
        $records | ForEach-Object {$_ | ConvertTo-Json -Depth 10 -Compress} |
            Set-Content -LiteralPath (Join-Path $sessions ('rollout-2026-11-18T15-20-00-'+$entry.id+'.jsonl')) -Encoding utf8
    }
    @'
param([string]$Root,[string]$Action,[string]$Payload)
$ErrorActionPreference='Stop'
function global:node.exe {
    $values=@($args)
    if($values[0] -cne (Join-Path $Root 'src/backend/CodexUsage.js') -or
       @($values | Where-Object {$_ -in @('--sessions','--thread-id','--thread-ids')}).Count -ne 1){
        throw 'This probe allows only read-only conversation metadata helpers.'
    }
    @{arguments=$values} | ConvertTo-Json -Compress | Add-Content -LiteralPath $env:CONTINUUM_PROBE_LOG -Encoding utf8
    & $env:CONTINUUM_PROBE_NODE @values
    $global:LASTEXITCODE=$LASTEXITCODE
}
function global:Get-ScheduledTask {
    [CmdletBinding()]param([string]$TaskName)
    # No native task query or mutation in this portable probe.
}
if($Action -eq 'metadata'){
    . (Join-Path $Root 'src/backend/CodexData.ps1')
    $entry=Get-CodexCliEntry
    if($entry -cne $env:CONTINUUM_PROBE_NATIVE){throw 'The isolated genuine native command was not selected.'}
    $request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload)) | ConvertFrom-Json
    $metadata=Get-CodexThreadMetadata -SessionId $request.sessionId -SourceDirectory $Root
    if(-not $metadata){throw 'Genuine Codex metadata did not cross the PowerShell/Node boundary.'}
    @{ok=$true;result=@{entry=$entry;metadata=$metadata}} | ConvertTo-Json -Depth 10 -Compress
    exit 0
}
& (Join-Path $Root 'src/desktop/windows_bridge.ps1') -Action $Action -Payload $Payload
if(-not $?){exit 1}
'@ | Set-Content -LiteralPath $wrapper -Encoding utf8

    $metadata=Invoke-GenuineBridge 'metadata' @{sessionId=$b}
    Require ($metadata.metadata.threadId -ceq $b -and $metadata.metadata.source -ceq 'cli') 'Genuine exact-ID/source metadata was lost.'
    Require ((Normalize $metadata.metadata.cwd) -eq (Normalize $outside)) 'Genuine non-Git metadata CWD changed across the boundary.'
    Require ($metadata.metadata.gitInfo.originUrl -ceq 'https://github.com/fixture/Horizon.git') 'Genuine stored Git metadata was lost.'
    $loaded=Invoke-GenuineBridge 'load'
    Require (@($loaded.sessions | Where-Object Id -eq $a).Count -eq 1 -and
             @($loaded.sessions | Where-Object Id -eq $b).Count -eq 1) 'The genuine Codex session inventory disappeared through the bridge.'
    $selected=Invoke-GenuineBridge 'select' @{sessionId=$a}
    Require ((Normalize $selected.found.Root) -eq (Normalize $repo)) 'Genuine current-directory metadata did not resolve the local checkout.'
    [void](Invoke-GenuineBridge 'save' @{draft=@{
        sessionId=$a;repo=$repo;model='fixture-model';effort='high';access='read-only';message='Fixture only.'
        runAt=(Get-Date).AddDays(2).ToString('yyyy-MM-ddTHH:mm:ss');executionMode='background';autoResumeOnLimit=$false
    }})
    $outsideSelection=Invoke-GenuineBridge 'select' @{sessionId=$b}
    Require ((Normalize $outsideSelection.found.Root) -eq (Normalize $repo)) 'Genuine non-Git session metadata did not resolve the exact remote through a known checkout.'
    $calls=@(Get-Content -LiteralPath $invocations | ForEach-Object {$_ | ConvertFrom-Json})
    Require ($calls.Count -ge 4 -and @($calls | Where-Object {$_.arguments -contains '--cli-js'}).Count -eq 0) 'The full bridge did not consistently select the genuine native entry.'
    Write-Host 'PASS: actual PowerShell dispatcher + installed-command resolver + Node metadata client + genuine native Codex + real Git; isolated credentials, no account/turn/resume calls.'
}finally{
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
}
