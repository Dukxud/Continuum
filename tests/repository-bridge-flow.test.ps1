# Real JSON bridge -> Node metadata protocol -> Git discovery -> preferences ->
# cancellation integration. Only Codex's external server and Windows task APIs
# are fixture providers. The production dispatcher and all internal helpers run
# unchanged in a fresh PowerShell child for every request, on Windows or Unix.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$bridge=Join-Path $root 'src/desktop/windows_bridge.ps1'
$powerShell=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$node=(Get-Command node -ErrorAction Stop).Source
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum-bridge-repositories-'+[guid]::NewGuid().ToString('N'))
$appData=Join-Path $fixture 'appdata'
$app=Join-Path $appData 'CodexResumeScheduler'
$codexHome=Join-Path $fixture 'codex'
$sessions=Join-Path $codexHome 'sessions/2026/11/18'
$outside=Join-Path $fixture 'outside-git'
$bin=Join-Path $fixture 'bin'
$mockDirectory=Join-Path $bin 'node_modules/@openai/codex/bin'
$metadataFile=Join-Path $fixture 'metadata.json'
$tasksFile=Join-Path $fixture 'tasks.json'
$protocolLog=Join-Path $fixture 'codex-protocol.jsonl'
$taskLog=Join-Path $fixture 'task-calls.jsonl'
$wrapper=Join-Path $fixture 'invoke-bridge.ps1'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Normalize([string]$Path){return $Path.Replace('\','/').TrimEnd('/')}
function Write-FixtureJson([string]$Path,$Value){
    $Value | ConvertTo-Json -Depth 16 -Compress | Set-Content -LiteralPath $Path -Encoding utf8
}
function New-FixtureRepository([string]$Name,[string]$Origin=''){
    $path=Join-Path $fixture ('checkouts/'+$Name)
    [void](New-Item -ItemType Directory -Path $path -Force)
    & git init -q -b main $path
    if($LASTEXITCODE -ne 0){throw 'Unable to create the isolated Git fixture.'}
    if($Origin){
        & git -C $path remote add origin $Origin
        if($LASTEXITCODE -ne 0){throw 'Unable to configure the isolated Git remote.'}
    }
    return $path
}
function Write-FixtureRollout([string]$Id,[object[]]$Records=@()){
    $file=Join-Path $sessions ('rollout-'+$Id+'.jsonl')
    $header=@{type='session_meta';payload=@{id=$Id;source='cli';cwd=$outside}}
    @($header)+$Records | ForEach-Object {$_ | ConvertTo-Json -Depth 14 -Compress} |
        Set-Content -LiteralPath $file -Encoding utf8
    return $file
}
function Invoke-FixtureBridge([string]$Action,$Body=@{},[switch]$ExpectFailure){
    $payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 16 -Compress)))
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$powerShell
    $start.UseShellExecute=$false
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',$wrapper,
        '-BridgePath',$bridge,'-BridgeAction',$Action,'-EncodedPayload',$payload)){
        $start.ArgumentList.Add($argument)
    }
    $start.Environment['LOCALAPPDATA']=$appData
    $start.Environment['CODEX_HOME']=$codexHome
    $start.Environment['PATH']=$bin+[IO.Path]::PathSeparator+$env:PATH
    $start.Environment['CONTINUUM_TEST_NODE']=$node
    $start.Environment['CONTINUUM_TEST_METADATA']=$metadataFile
    $start.Environment['CONTINUUM_TEST_TASKS']=$tasksFile
    $start.Environment['CONTINUUM_TEST_PROTOCOL_LOG']=$protocolLog
    $start.Environment['CONTINUUM_TEST_TASK_LOG']=$taskLog
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$start
    try{
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(45000)){
            $process.Kill($true)
            throw "Bridge $Action exceeded the integration-test deadline."
        }
        $output=$stdout.GetAwaiter().GetResult()
        $errors=$stderr.GetAwaiter().GetResult()
        $lines=@($output -split '\r?\n' | Where-Object {$_})
        Require ($lines.Count -eq 1) "Bridge $Action must emit exactly one JSON response: $output $errors"
        $reply=$lines[0] | ConvertFrom-Json -ErrorAction Stop
        if($ExpectFailure){
            Require ($process.ExitCode -ne 0 -and $reply.ok -eq $false) "Bridge $Action unexpectedly succeeded."
        }else{
            Require ($process.ExitCode -eq 0 -and $reply.ok -eq $true) "Bridge $Action failed: $($reply.error) $errors"
        }
        return $reply
    }finally{$process.Dispose()}
}
function Save-FixtureChoice([string]$Id,[string]$Repository){
    return Invoke-FixtureBridge 'save' @{draft=@{
        sessionId=$Id;repo=$Repository;model='gpt-test';effort='high';access='read-only'
        message='Resume the isolated fixture.';runAt=(Get-Date).AddDays(2).ToString('yyyy-MM-ddTHH:mm:ss')
        executionMode='background';autoResumeOnLimit=$false
    }}
}
function Add-FixtureTask([string]$Name,[string]$Id,[string]$Repository,[string]$State='Ready'){
    $tasks=Get-Content -LiteralPath $tasksFile -Raw | ConvertFrom-Json -AsHashtable
    $tasks[$Name]=@{TaskName=$Name;TaskPath='\';State=$State
        Triggers=@(@{StartBoundary=(Get-Date).AddDays(2).ToString('yyyy-MM-ddTHH:mm:ss')})}
    Write-FixtureJson $tasksFile $tasks
    Write-FixtureJson (Join-Path $app ($Name+'.json')) @{sessionId=$Id;repo=$Repository}
}

[void](New-Item -ItemType Directory -Path $app,$sessions,$outside,$mockDirectory -Force)
try{
    # The shim is found through the same npm installation layout as production.
    # It must never itself execute: CodexUsage.js starts the fake JS server.
    $shim=Join-Path $bin 'codex.cmd'
    if($IsWindows){'@exit /b 99' | Set-Content -LiteralPath $shim -Encoding ascii}
    else{
        "#!/bin/sh`nexit 99" | Set-Content -LiteralPath $shim -Encoding ascii
        & chmod +x $shim
        Require ($LASTEXITCODE -eq 0) 'Could not make the test command discoverable.'
    }
    @'
"use strict";
const fs=require("node:fs");
const readline=require("node:readline");
if(JSON.stringify(process.argv.slice(2))!==JSON.stringify(["app-server","--listen","stdio://"]))
  throw new Error("Only the metadata App Server may start in this fixture");
let initialized=false;
const send=value=>process.stdout.write(JSON.stringify(value)+"\n");
readline.createInterface({input:process.stdin}).on("line",line=>{
  const message=JSON.parse(line);
  fs.appendFileSync(process.env.CONTINUUM_TEST_PROTOCOL_LOG,line+"\n");
  if(message.method==="initialize")return send({id:message.id,result:{}});
  if(message.method==="initialized"){initialized=true;return;}
  if(!initialized)throw new Error("Metadata handshake missing");
  const data=JSON.parse(fs.readFileSync(process.env.CONTINUUM_TEST_METADATA,"utf8").replace(/^\uFEFF/,""));
  if(message.method==="thread/list"){
    if(message.params.sortKey!=="updated_at" || message.params.archived!==false ||
       JSON.stringify(message.params.sourceKinds)!=='["cli","exec"]')
      throw new Error("Incorrect metadata inventory filters");
    return send({id:message.id,result:{data:Object.values(data.threads).filter(t=>!t.omitFromList).slice(0,message.params.limit),nextCursor:null}});
  }
  if(message.method==="thread/read"){
    if(message.params.includeTurns!==false)throw new Error("Repository discovery requested history hydration");
    const thread=data.threads[message.params.threadId];
    return send(thread?{id:message.id,result:{thread}}:{id:message.id,error:{message:"Unknown fixture thread"}});
  }
  throw new Error("Unexpected account or execution request: "+message.method);
});
'@ | Set-Content -LiteralPath (Join-Path $mockDirectory 'codex.js') -Encoding utf8
    @'
param([string]$BridgePath,[string]$BridgeAction,[string]$EncodedPayload)
$ErrorActionPreference='Stop'
# Only adapt the executable spelling on Unix; IsWindows and production code
# are unchanged. Node still runs the real CodexUsage.js protocol client.
if(-not $IsWindows){
    function global:node.exe {
        & $env:CONTINUUM_TEST_NODE @args
        $global:LASTEXITCODE=$LASTEXITCODE
    }
}
function global:Write-FixtureTaskCall([string]$Operation,[string]$TaskName){
    @{operation=$Operation;name=$TaskName} | ConvertTo-Json -Compress |
        Add-Content -LiteralPath $env:CONTINUUM_TEST_TASK_LOG -Encoding utf8
}
function global:Get-ScheduledTask {
    [CmdletBinding()]param([string]$TaskName)
    Write-FixtureTaskCall 'get' $TaskName
    $tasks=Get-Content -LiteralPath $env:CONTINUUM_TEST_TASKS -Raw | ConvertFrom-Json -AsHashtable
    foreach($name in $tasks.Keys){if($name -like $TaskName){[pscustomobject]$tasks[$name]}}
}
function global:Get-ScheduledTaskInfo {
    [CmdletBinding()]param([string]$TaskName,[string]$TaskPath)
    Write-FixtureTaskCall 'info' $TaskName
    [pscustomobject]@{LastRunTime=[datetime]'1900-01-01';LastTaskResult=0}
}
function global:Unregister-ScheduledTask {
    [CmdletBinding()]param([string]$TaskName,[switch]$Confirm)
    Write-FixtureTaskCall 'unregister' $TaskName
    $tasks=Get-Content -LiteralPath $env:CONTINUUM_TEST_TASKS -Raw | ConvertFrom-Json -AsHashtable
    if(-not $tasks.Contains($TaskName)){throw 'Fixture task not found.'}
    $tasks.Remove($TaskName)
    $tasks | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $env:CONTINUUM_TEST_TASKS -Encoding utf8
}
& $BridgePath -Action $BridgeAction -Payload $EncodedPayload
if(-not $?){exit 1}
'@ | Set-Content -LiteralPath $wrapper -Encoding utf8
    Write-FixtureJson $tasksFile @{}

    $a='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $b='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    $c='cccccccc-cccc-cccc-cccc-cccccccccccc'
    $d='dddddddd-dddd-dddd-dddd-dddddddddddd'
    $legacy='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
    $foreign='ffffffff-ffff-ffff-ffff-ffffffffffff'
    $unsupported='11111111-1111-1111-1111-111111111111'
    $repoA=New-FixtureRepository 'renamed-horizon-checkout' 'https://github.com/fixture/Horizon.git'
    $repoB=New-FixtureRepository 'current-checkout'
    $repoLegacy=New-FixtureRepository 'legacy-only-checkout'
    $rolloutA=Write-FixtureRollout $a @(@{type='event_msg';payload=@{
        type='item_completed';thread_id=$a;turn_id='fixture-turn';item=@{
            type='CommandExecution';id='command-1';cwd=$repoA;command=@('git','status');status='completed'
        }
    }})
    $rolloutB=Write-FixtureRollout $b @(@{type='event_msg';payload=@{
        type='item_completed';thread_id=$a;item=@{type='CommandExecution';cwd=$repoB}
    }})
    $compressed=Join-Path $sessions ('rollout-'+$c+'.jsonl.zst')
    # Opaque compressed-path fixture: successful discovery must use authoritative
    # metadata rather than treating compressed bytes as a readable JSONL.
    [IO.File]::WriteAllBytes($compressed,[byte[]]@(0x28,0xB5,0x2F,0xFD))
    [void](Write-FixtureRollout $unsupported)
    $metadata=@{threads=@{}}
    $metadata.threads[$a]=@{id=$a;source='cli';cwd=$outside;path=$rolloutA;preview='';name='A';updatedAt=1795040006}
    $metadata.threads[$b]=@{id=$b;source='cli';cwd=$outside;path=$rolloutB;preview='';name='B';updatedAt=1795040005}
    $metadata.threads[$c]=@{id=$c;source='cli';cwd=$outside;path=$compressed;preview='Review the inherited project.'
        gitInfo=@{originUrl='https://github.com/fixture/Horizon.git'};name='Horizon';updatedAt=1795040004}
    $metadata.threads[$d]=@{id=$d;source='exec';cwd=$repoB;path=$null;preview='';name='D';updatedAt=1795040003}
    $metadata.threads[$legacy]=@{id=$legacy;source='cli';cwd=$outside;path=$null;preview='';name='Legacy';updatedAt=1795040002}
    $metadata.threads[$foreign]=@{id=$a;source='cli';cwd=$repoA;path=$rolloutA;preview='';omitFromList=$true}
    $metadata.threads[$unsupported]=@{id=$unsupported;source='vscode';cwd=$repoA;path=$null;preview='';updatedAt=1795040001}
    Write-FixtureJson $metadataFile $metadata

    $loaded=(Invoke-FixtureBridge 'load').result
    Require (@($loaded.sessions | Where-Object Id -eq $c).Count -eq 1) 'Compressed Codex thread disappeared from the real bridge inventory.'
    Require (@($loaded.sessions | Where-Object Id -eq $d).Count -eq 1) 'Metadata-only exec thread disappeared from the real bridge inventory.'
    $selected=(Invoke-FixtureBridge 'select' @{sessionId=$a}).result
    Require ((Normalize $selected.found.Root) -eq (Normalize $repoA)) 'Actual bridge did not resolve modern structured command evidence.'

    [void](Save-FixtureChoice $a $repoA)
    [void](Save-FixtureChoice $b '')
    $saved=Get-Content -LiteralPath (Join-Path $app 'settings.json') -Raw | ConvertFrom-Json
    Require ($saved.draft.sessionId -eq $b -and -not $saved.draft.repo) 'Second draft was not saved independently.'
    $compressedSelection=(Invoke-FixtureBridge 'select' @{sessionId=$c}).result
    Require ((Normalize $compressedSelection.found.Root) -eq (Normalize $repoA)) 'Compressed thread metadata did not resolve its exact Git remote through a known checkout.'

    $jobA='CodexResume-20261118-1200-abcdef01'
    Add-FixtureTask $jobA $a $repoA
    $cancelled=(Invoke-FixtureBridge 'cancel' @{name=$jobA}).result
    Require ($cancelled.status -eq 'Cancelled' -and -not $cancelled.warning) 'Actual cancellation did not complete.'
    Require (-not (Test-Path -LiteralPath (Join-Path $app ($jobA+'.json')))) 'Cancellation left the job payload in place.'
    $outcome=Get-Content -LiteralPath (Join-Path $app ($jobA+'.result.json')) -Raw | ConvertFrom-Json
    Require ($outcome.status -eq 'cancelled') 'Cancellation did not write its real durable outcome.'
    [void](Write-FixtureRollout $a)
    Write-FixtureJson (Join-Path $app 'settings.json') @{version=1;draft=@{sessionId=$b;repo=''}}
    $restored=(Invoke-FixtureBridge 'select' @{sessionId=$a}).result
    Require ((Normalize $restored.found.Root) -eq (Normalize $repoA)) 'Fresh bridge process lost A after B draft, task cancellation, evidence removal, and legacy settings replacement.'
    $unrelated=(Invoke-FixtureBridge 'select' @{sessionId=$b}).result
    Require ($null -eq $unrelated.found) 'B inherited another thread association or accepted a foreign thread_id event.'

    $manual=(Invoke-FixtureBridge 'select' @{sessionId=$d;repository=$repoA}).result
    Require ((Normalize $manual.found.Root) -eq (Normalize $repoA)) 'Restored verified manual repository was replaced by automatic metadata.'
    Require ($manual.found.Source -eq 'saved repository selection' -and
        @($manual.found.AlternativeRoots | Where-Object {(Normalize $_) -eq (Normalize $repoB)}).Count -eq 1) 'Manual restoration discarded the current metadata alternative.'
    $healed=(Invoke-FixtureBridge 'select' @{sessionId=$d;repository=(Join-Path $fixture 'missing-old-checkout')}).result
    Require ((Normalize $healed.found.Root) -eq (Normalize $repoB)) 'Missing restored repository prevented fresh verified discovery.'

    $legacyJob='CodexResume-20261118-1201-abcdef02'
    Add-FixtureTask $legacyJob $legacy $repoLegacy
    Require (-not (Test-Path -LiteralPath (Join-Path $app ('session-repositories/'+$legacy+'.json')))) 'Legacy fixture unexpectedly had a saved association.'
    [void](Invoke-FixtureBridge 'cancel' @{name=$legacyJob})
    $legacyRestored=(Invoke-FixtureBridge 'select' @{sessionId=$legacy}).result
    Require ((Normalize $legacyRestored.found.Root) -eq (Normalize $repoLegacy)) 'Cancelling an old job without a preference save deleted its sole repository evidence.'

    $rejected=Invoke-FixtureBridge 'select' @{sessionId=$foreign} -ExpectFailure
    Require ($rejected.error -match 'could not be verified') 'Wrong-ID server metadata was not rejected at the session boundary.'
    $rejected=Invoke-FixtureBridge 'select' @{sessionId=$unsupported} -ExpectFailure
    Require ($rejected.error -match 'could not be verified') 'A stale local CLI header overrode a positively unsupported server source.'
    foreach($source in @(@{custom='cli'},@{subAgent='review'},@{futureSource='cli'},'',42)){
        $metadata.threads[$unsupported].source=$source
        Write-FixtureJson $metadataFile $metadata
        $rejected=Invoke-FixtureBridge 'select' @{sessionId=$unsupported} -ExpectFailure
        Require ($rejected.error -match 'could not be verified') 'An explicit structured or malformed source became missing metadata and accepted a stale local CLI header.'
    }
    $metadata.threads[$unsupported].source=$null
    Write-FixtureJson $metadataFile $metadata
    $legacySource=(Invoke-FixtureBridge 'select' @{sessionId=$unsupported}).result
    Require ((Normalize $legacySource.found.Root) -eq (Normalize $repoA)) 'An omitted legacy source stopped a matching local CLI header from verifying the thread.'
    $running='CodexResume-20261118-1202-abcdef03'
    Add-FixtureTask $running $a $repoA 'Running'
    $rejected=Invoke-FixtureBridge 'cancel' @{name=$running} -ExpectFailure
    Require ($rejected.error -match 'cannot safely cancel') 'Running task cancellation bypassed the native pre-start guard.'
    Require (Test-Path -LiteralPath (Join-Path $app ($running+'.json'))) 'Rejected cancellation deleted an active payload.'
    Require (-not (Test-Path -LiteralPath (Join-Path $app ($running+'.result.json')))) 'Rejected cancellation fabricated a cancelled outcome.'

    $calls=@(Get-Content -LiteralPath $taskLog | ForEach-Object {$_ | ConvertFrom-Json})
    $unregistered=@($calls | Where-Object operation -eq 'unregister')
    Require ($unregistered.Count -eq 2 -and $unregistered[0].name -eq $jobA -and $unregistered[1].name -eq $legacyJob) 'Cancellation did not use precisely the two authorized fixture task removals.'
    Require (@($calls | Where-Object operation -eq 'info').Count -eq 2) 'Cancellation did not verify previous execution history before removal.'
    $requests=@(Get-Content -LiteralPath $protocolLog | ForEach-Object {$_ | ConvertFrom-Json})
    Require (@($requests | Where-Object {$_.method -notin @('initialize','initialized','thread/read','thread/list')}).Count -eq 0) 'Repository flow made an account or execution request.'
    Require (@($requests | Where-Object {$_.method -eq 'thread/read' -and $_.params.includeTurns -ne $false}).Count -eq 0) 'Repository flow hydrated or resumed a conversation.'
    Write-Host 'PASS: real bridge JSON, modern/compressed metadata, verified manual restore, missing-path healing, independent saves, actual cancellation migration, identity boundaries, and pre-start guard.'
}finally{
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
}
