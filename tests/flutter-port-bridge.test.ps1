# Read-only integration test of the actual Windows JSON bridge.
# No scheduled task creation, cancellation, or login state changes.
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows required for bridge integration.'}
$project=Join-Path (Split-Path -Parent $PSScriptRoot) 'flutter_port'
$bridge=Join-Path $project 'windows_bridge.ps1'
if(-not (Test-Path -LiteralPath $bridge -PathType Leaf)){throw 'Flutter JSON bridge missing.'}
foreach($action in @('load','pending')){
    $output=@(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action $action)
    $exitCode=$LASTEXITCODE
    if(-not $output){throw "Flutter $action bridge returned no result (exit $exitCode)."}
    try{
        $body=($output | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    }catch{
        throw "Flutter $action response was invalid JSON (exit $exitCode): $($output -join '; ')"
    }
    if($exitCode -ne 0 -or $body.ok -ne $true){
        throw "Flutter $action bridge failed (exit $exitCode): $($body.error)"
    }
    if($null -eq $body.result -or $body.result.pending -isnot [array] -or $body.result.history -isnot [array]){
        throw "Flutter $action response is missing scheduler lists."
    }
    if($action -eq 'load' -and $body.result.sessions -isnot [array]){
        throw 'Flutter load response is missing saved conversation list.'
    }
    Write-Host "Flutter Windows $action read-only integration PASS." -ForegroundColor Green
}

# A real Windows bridge integration check: the same CodexData functions used
# by WinForms must resolve the Git root for a selected saved CLI session.
# A disposable CODEX_HOME prevents access to the operator's real conversations.
$originalCodexHome=$env:CODEX_HOME
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('flutter-repository-selection-'+[guid]::NewGuid().ToString('N'))
try {
    $repository=Join-Path $fixture 'qa-repository'
    $sessions=Join-Path $fixture 'codex-home\sessions\2026\11\04'
    [void](New-Item -ItemType Directory -Path $repository,$sessions -Force)
    & git init -b main $repository | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Unable to initialize disposable Git fixture.'}
    $sessionId=[guid]::NewGuid().ToString()
    $metadata=@{type='session_meta';payload=@{
        id=$sessionId;source='exec';cwd=$repository
    }} | ConvertTo-Json -Depth 8 -Compress
    Set-Content -LiteralPath (Join-Path $sessions ('rollout-'+$sessionId+'.jsonl')) -Value $metadata -Encoding utf8
    # The latest explicit user activity identifies a session more reliably
    # than its original working directory or a guessed conversation title.
    $gitRollout=Join-Path $sessions ('rollout-'+$sessionId+'.jsonl')
    $userActivity=@{type='event_msg';payload=@{
        type='user_message';message='Review shared-EC2 architecture'
    }} | ConvertTo-Json -Depth 8 -Compress
    Add-Content -LiteralPath $gitRollout -Value $userActivity -Encoding utf8
    $env:CODEX_HOME=Join-Path $fixture 'codex-home'
    $payload=@{sessionId=$sessionId} | ConvertTo-Json -Compress
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $output=@(& pwsh -NoLogo -NoProfile -NonInteractive -STA -File $bridge -Action select -Payload $encoded)
    $exitCode=$LASTEXITCODE
    if(-not $output){throw "Bridge select returned no response (exit $exitCode)."}
    $answer=($output | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($exitCode -ne 0 -or $answer.ok -ne $true){
        throw "Bridge select rejected disposable session (exit $exitCode): $($answer.error)"
    }
    if($answer.result.sessionId -cne $sessionId){
        throw "Bridge selected the wrong session (expected $sessionId)."
    }
    $actual=[string]$answer.result.found.Root
    $expected=(& git -C $repository rev-parse --show-toplevel)
    if($LASTEXITCODE -ne 0){throw 'Git root verification failed.'}
    $actual=$actual.Replace('\','/').TrimEnd('/')
    $expected=([string]$expected).Replace('\','/').TrimEnd('/')
    if($actual -ine $expected){
        throw "Flutter bridge must resolve the original CodexData Git root. Expected '$expected', found '$actual'."
    }
    Write-Host 'Flutter real bridge selected disposable Git-backed CLI session PASS.' -ForegroundColor Green

    # The same resolver must *not* borrow that root for a different CLI
    # conversation whose recorded directory is outside any Git checkout.
    $outside=Join-Path $fixture 'outside-git'
    [void](New-Item -ItemType Directory -Path $outside)
    $otherId=[guid]::NewGuid().ToString()
    $otherMeta=@{type='session_meta';payload=@{
        id=$otherId;source='cli';cwd=$outside
    }} | ConvertTo-Json -Depth 8 -Compress
    Set-Content -LiteralPath (Join-Path $sessions ('rollout-'+$otherId+'.jsonl')) -Value $otherMeta -Encoding utf8
    $otherPayload=@{sessionId=$otherId} | ConvertTo-Json -Compress
    $otherEncoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($otherPayload))
    $otherOutput=@(& pwsh -NoLogo -NoProfile -NonInteractive -STA -File $bridge -Action select -Payload $otherEncoded)
    $otherExit=$LASTEXITCODE
    if(-not $otherOutput){throw "Non-repository CLI selection produced no response (exit $otherExit)."}
    $otherAnswer=($otherOutput | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($otherExit -ne 0 -or $otherAnswer.ok -ne $true){
        throw "Non-repository CLI selection failed rather than remaining unresolved: $($otherAnswer.error)"
    }
    if($null -ne $otherAnswer.result.found){
        throw "Unrelated CLI session must not inherit another session's Git repository."
    }
    Write-Host 'Flutter real bridge correctly leaves a non-Git CLI session unresolved PASS.' -ForegroundColor Green
    $listed=@(& pwsh -NoLogo -NoProfile -NonInteractive -STA -File $bridge -Action load)
    $listedExit=$LASTEXITCODE
    if($listedExit -ne 0 -or -not $listed){throw "Could not list disposable sessions (exit $listedExit)."}
    $listedResult=($listed | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($listedResult.ok -ne $true){throw "Cannot list sessions: $($listedResult.error)"}
    $gitSession=@($listedResult.result.sessions | Where-Object Id -eq $sessionId)
    $outsideSession=@($listedResult.result.sessions | Where-Object Id -eq $otherId)
    if($gitSession.Count -ne 1 -or $outsideSession.Count -ne 1){
        throw 'Git-backed and non-Git sessions must both appear in the chooser.'
    }
    if(-not $gitSession[0].Display.StartsWith('Git: qa-repository | ') -or
       -not $gitSession[0].Display.EndsWith($sessionId.Substring(28))){
        throw 'Git-backed session label must show the project, time and short ID.'
    }
    if(-not $outsideSession[0].Display.StartsWith('Outside Git: outside-git | ') -or
       -not $outsideSession[0].Display.EndsWith($otherId.Substring(28))){
        throw 'Non-Git session label must distinguish its starting folder, time and short ID.'
    }
    if($gitSession[0].Display.Contains($sessionId) -or
       $outsideSession[0].Display.Contains($otherId)){
        throw 'Full UUID must not crowd out session identity in the chooser.'
    }
    $displayStamp=(Get-Item -LiteralPath (Join-Path $sessions ('rollout-'+$sessionId+'.jsonl'))).LastWriteTime.ToString('d MMM HH:mm',[Globalization.CultureInfo]::InvariantCulture)
    if(-not $gitSession[0].Display.Contains(" | $displayStamp | ")){
        throw 'Session chooser date must use day then abbreviated month.'
    }
    if($gitSession[0].Display.Contains('Review shared-EC2 architecture')){
        throw 'Essential startup load unexpectedly depends on optional rollout content.'
    }
    $labelOutput=@(& pwsh -NoLogo -NoProfile -NonInteractive -STA -File $bridge -Action labels)
    $labelExit=$LASTEXITCODE
    if($labelExit -ne 0 -or -not $labelOutput){throw 'Optional activity-label query failed.'}
    $labelBody=($labelOutput | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($labelBody.ok -ne $true){throw "Optional labels failed: $($labelBody.error)"}
    $gitLabel=@($labelBody.result.sessions | Where-Object Id -eq $sessionId)
    $outsideLabel=@($labelBody.result.sessions | Where-Object Id -eq $otherId)
    if($gitLabel.Count -ne 1 -or
       -not $gitLabel[0].Display.StartsWith('Review shared-EC2 architecture | Git: qa-repository | ') -or
       $outsideLabel.Count -ne 1 -or
       -not $outsideLabel[0].Display.StartsWith('Outside Git: outside-git | ')){
        throw 'Optional activity query lost its topic, fallback label or stable session identity.'
    }
    # A canonical Codex-owned thread title must override the opening prompt.
    # Fake local App Server: no account access, network, or Windows task mutation.
    $savedPath=$env:PATH
    try {
        $bin=Join-Path $fixture 'mock-codex-bin'
        $mockDir=Join-Path $bin 'node_modules\@openai\codex\bin'
        [void](New-Item -ItemType Directory -Path $mockDir -Force)
        '@echo off' | Set-Content -LiteralPath (Join-Path $bin 'codex.cmd') -Encoding ascii
        $mock=@'
"use strict";
const readline=require("node:readline");
readline.createInterface({input:process.stdin}).on("line",line=>{
 let message;try{message=JSON.parse(line)}catch{return}
 const send=answer=>process.stdout.write(JSON.stringify(answer)+"\n");
 if(message.method==="initialize")send({id:message.id,result:{}});
 if(message.method==="thread/read") {
   send({id:message.id,result:{thread:{
     id:message.params.threadId,name:null,preview:"# AIVault — Independent Adversarial Architecture Review"
   }}});
 }
 if(message.method==="thread/list") {
   if(message.params.sourceKinds?.join(",")!=="cli,exec")
     return send({id:message.id,error:{message:"Expected CLI/exec only"}});
   send({id:message.id,result:{data:[
     {id:"__TITLE_ID__",name:"AIV",preview:"# AIVault — Independent Adversarial Architecture Review",cwd:"C:\\QA"}
   ],nextCursor:null}});
 }
});
'@
        $mock=$mock.Replace('__TITLE_ID__',$sessionId)
        Set-Content -LiteralPath (Join-Path $mockDir 'codex.js') -Value $mock -Encoding utf8
        $env:PATH="$bin;$savedPath"
        $namedOutput=@(& pwsh -NoLogo -NoProfile -NonInteractive -STA -File $bridge -Action labels)
        if($LASTEXITCODE -ne 0 -or -not $namedOutput){throw 'Canonical title bridge query failed.'}
        $namedBody=($namedOutput | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
        if($namedBody.ok -ne $true){throw "Canonical title bridge error: $($namedBody.error)"}
        $namedSession=@($namedBody.result.sessions | Where-Object Id -eq $sessionId)
        if($namedSession.Count -ne 1 -or
           -not $namedSession[0].Display.StartsWith('AIV | Git: qa-repository | ')){
            throw 'Bridge ignored the resume picker thread/list name and used stale thread/read or rollout text.'
        }
        Write-Host 'Codex resume picker title wins over stale thread/read and rollout text PASS.' -ForegroundColor Green
    }finally{$env:PATH=$savedPath}
    Write-Host 'Essential session loading is isolated from optional activity excerpts PASS.' -ForegroundColor Green
    Write-Host 'Flutter conversation labels clearly distinguish Git-backed and outside-Git sessions PASS.' -ForegroundColor Green

} finally {
    if($null -eq $originalCodexHome){Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue}
    else{$env:CODEX_HOME=$originalCodexHome}
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}

# Exercise Flutter's actual JSON-in/JSON-out scheduling boundary, without
# contacting Codex or registering any task: the all-zero session is unverified
# and the repository path is deliberately empty.
function Assert-ScheduleRejected {
    param([Parameter(Mandatory)][string]$RunAt,[Parameter(Mandatory)][string]$Expected)
    $payload=@{
        sessionId='00000000-0000-0000-0000-000000000000'
        runAt=$RunAt
        repo=''
    } | ConvertTo-Json -Compress
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $output=@(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action schedule -Payload $encoded)
    $exit=$LASTEXITCODE
    if(-not $output){throw "Schedule preflight returned no response for $RunAt"}
    $answer=($output | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($exit -eq 0 -or $answer.ok -ne $false -or $answer.error -cne $Expected){
        throw "Schedule preflight '$RunAt' expected '$Expected', got '$($answer.error)' (exit $exit)"
    }
}
$future=(Get-Date).AddDays(2).Date.AddHours(13).AddSeconds(37).ToString(
    'yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
Assert-ScheduleRejected -RunAt $future -Expected 'Selected CLI session not verified.'
Assert-ScheduleRejected -RunAt ($future+'Z') -Expected 'Invalid local run time.'
Assert-ScheduleRejected -RunAt ($future+'-06:00') -Expected 'Invalid local run time.'
Assert-ScheduleRejected -RunAt '2026-11-04 10:13:00' -Expected 'Invalid local run time.'
Assert-ScheduleRejected -RunAt ((Get-Date).AddMinutes(-3).ToString('yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)) -Expected 'Choose a time at least 30 seconds ahead.'

# The versioned quota policy is opt-in; reject text or numbers rather than
# allowing truthy coercion to turn unattended retries on.
$invalid=@{
    sessionId='00000000-0000-0000-0000-000000000000'
    runAt=$future
    autoResumeOnLimit='true'
} | ConvertTo-Json -Compress
$invalidPayload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($invalid))
$invalidOutput=@(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action schedule -Payload $invalidPayload)
$invalidExit=$LASTEXITCODE
$invalidAnswer=($invalidOutput | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
if($invalidExit -eq 0 -or $invalidAnswer.error -cne 'Invalid automatic-continuation option.'){
    throw 'A non-boolean continuation flag was not rejected before task creation.'
}

# Execution-mode validation must happen before looking up a real
# conversation, verifying quota or registering a Windows task.
function Assert-ModeRejected {
    param([hashtable]$Flags,[string]$Expected)
    $payload=@{
        sessionId='00000000-0000-0000-0000-000000000000'
        runAt=$future
        repo=''
    }
    foreach($entry in $Flags.GetEnumerator()){$payload[$entry.Key]=$entry.Value}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress)))
    $output=@(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action schedule -Payload $encoded)
    $exitCode=$LASTEXITCODE
    $reply=($output | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($exitCode -eq 0 -or $reply.error -cne $Expected){
        throw "Invalid execution-mode request was not rejected before scheduling: $($reply.error)"
    }
}
Assert-ModeRejected -Flags @{executionMode='terminal;Write-Host hacked'} -Expected 'Invalid execution mode.'
Assert-ModeRejected -Flags @{executionMode='terminal';autoResumeOnLimit=$true} -Expected 'Automatic quota continuation requires Background execution.'
Write-Host 'Flutter strict local-time JSON schedule preflight PASS (no task mutation).' -ForegroundColor Green

# Saving preferences must preserve the opt-in flag. Use an isolated settings
# location so this test cannot mutate the operator's real preferences.
$oldLocalAppData=$env:LOCALAPPDATA
$settingsFixture=Join-Path ([IO.Path]::GetTempPath()) ('flutter-save-fixture-'+[guid]::NewGuid().ToString('N'))
try {
    $env:LOCALAPPDATA=$settingsFixture
    $draft=@{
        sessionId='11111111-1111-1111-1111-111111111111'
        repo='C:\fixture\repo';model='gpt-test';effort='medium'
        access='read-only';message='Resume.';runAt=$future
        executionMode='background';autoResumeOnLimit=$true
    }
    $body=@{draft=$draft;compactMode=$true;microMode=$true;alwaysOnTop=$true} | ConvertTo-Json -Compress -Depth 6
    $payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
    $output=@(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action save -Payload $payload)
    $status=$LASTEXITCODE
    if($status -ne 0 -or -not $output){throw 'Flutter isolated preferences save failed.'}
    $reply=($output | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($reply.ok -ne $true){throw "Preferences save rejected: $($reply.error)"}
    $saved=Get-Content -LiteralPath (Join-Path $settingsFixture 'CodexResumeScheduler\settings.json') -Raw | ConvertFrom-Json
    if($saved.draft.autoResumeOnLimit -ne $true -or $saved.draft.repo -cne 'C:\fixture\repo' -or
       $saved.microMode -ne $true -or $saved.alwaysOnTop -ne $true -or $saved.compactMode -ne $true -or
       $saved.draft.executionMode -cne 'background'){
        throw 'Persisted preferences lost the auto-resume opt-in or repository.'
    }
    $draft.autoResumeOnLimit='true'
    $bad=@{draft=$draft;compactMode=$false} | ConvertTo-Json -Compress -Depth 6
    $badPayload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bad))
    $badOutput=@(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action save -Payload $badPayload)
    $badExit=$LASTEXITCODE
    $badReply=($badOutput | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($badExit -eq 0 -or $badReply.error -cne 'Invalid saved quota continuation option.'){
        throw 'Untrusted automatic-continuation setting was accepted.'
    }
    $draft.autoResumeOnLimit=$true
    foreach($flag in @('microMode','alwaysOnTop')){
        $request=@{draft=$draft;compactMode=$true;microMode=$true;alwaysOnTop=$true}
        $request[$flag]='true'
        $invalidBody=$request | ConvertTo-Json -Compress -Depth 6
        $invalidPayload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($invalidBody))
        $invalidOut=@(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action save -Payload $invalidPayload)
        $invalidExit=$LASTEXITCODE
        $invalidReply=($invalidOut | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
        if($invalidExit -eq 0 -or $invalidReply.error -cne "Invalid window preference: $flag"){
            throw "Invalid persisted $flag preference was accepted."
        }
    }
    # Native interactive sessions are explicit and cannot silently inherit
    # unattended quota continuation. These are read-only contract checks.
    $draft.autoResumeOnLimit=$false
    $draft.executionMode='terminal'
    $terminalPayload=@{draft=$draft;compactMode=$false} | ConvertTo-Json -Compress -Depth 6
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($terminalPayload))
    $terminalReply=(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action save -Payload $encoded | Select-Object -Last 1) | ConvertFrom-Json
    if($terminalReply.ok -ne $true){throw "Interactive draft could not be saved: $($terminalReply.error)"}
    $terminalSaved=Get-Content -LiteralPath (Join-Path $settingsFixture 'CodexResumeScheduler/settings.json') -Raw | ConvertFrom-Json
    if($terminalSaved.draft.executionMode -cne 'terminal'){throw 'Saved native-terminal mode was lost.'}
    $draft.autoResumeOnLimit=$true
    $conflict=@{draft=$draft;compactMode=$false} | ConvertTo-Json -Compress -Depth 6
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($conflict))
    $conflictReply=(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action save -Payload $encoded | Select-Object -Last 1) | ConvertFrom-Json
    if($conflictReply.ok -ne $false -or $conflictReply.error -cne 'Automatic quota continuation requires Background execution.'){
        throw 'Interactive terminal incorrectly accepted unattended quota continuation.'
    }
    $draft.autoResumeOnLimit=$false
    $draft.executionMode='background;Write-Host hacked'
    $invalidMode=@{draft=$draft;compactMode=$false} | ConvertTo-Json -Compress -Depth 6
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($invalidMode))
    $modeReply=(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action save -Payload $encoded | Select-Object -Last 1) | ConvertFrom-Json
    if($modeReply.ok -ne $false -or $modeReply.error -cne 'Invalid saved execution mode.'){
        throw 'Untrusted execution mode was accepted.'
    }
    Write-Host 'Flutter isolated preferences round-trip and strict opt-in validation PASS.' -ForegroundColor Green
}finally{
    if($null -eq $oldLocalAppData){Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue}
    else{$env:LOCALAPPDATA=$oldLocalAppData}
    if(Test-Path -LiteralPath $settingsFixture){
        Remove-Item -LiteralPath $settingsFixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}

