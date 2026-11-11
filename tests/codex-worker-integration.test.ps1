# End-to-end worker process tests with a local fake Codex CLI and App Server.
# Never contacts the user's account, creates Windows tasks, or runs real Codex.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/backend/CodexData.ps1')
. (Join-Path $root 'src/backend/CodexRunEngine.ps1')
function Require($ok,[string]$message){if(-not $ok){throw $message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('codex-worker-mock-' + [guid]::NewGuid().ToString('N'))
try {
    $bin=Join-Path $temp 'bin'
    $cliFolder=Join-Path $bin 'node_modules/@openai/codex/bin'
    [void](New-Item -ItemType Directory -Path $cliFolder -Force)
    $cli=Join-Path $cliFolder 'codex.js'
    @'
'use strict';
const fs=require('node:fs');
if(process.argv.includes('app-server')){
 const rl=require('node:readline').createInterface({input:process.stdin});
 rl.on('line',line=>{
  const m=JSON.parse(line);
  if(m.method==='initialize')process.stdout.write(JSON.stringify({id:m.id,result:{userAgent:'test'}})+'\n');
  if(m.method==='thread/read'){
   if(process.env.CODEX_STUB_THREAD_MISSING==='1')process.stdout.write(JSON.stringify({id:m.id,error:{message:'Thread not found'}})+'\n');
   else process.stdout.write(JSON.stringify({id:m.id,result:{thread:{id:m.params.threadId,cwd:process.env.CODEX_STUB_REPO||process.cwd()}}})+'\n');
  }
  if(m.method==='account/read')process.stdout.write(JSON.stringify({id:m.id,result:{account:{type:'chatgpt',email:'worker@example.test'},workspaceRouting:process.env.CODEX_STUB_ACCOUNT==='missing'?{}:{chatgptAccountId:process.env.CODEX_STUB_ACCOUNT||'acct-1',backendOrigin:'https://chatgpt.com',accountRoutingOverride:'NO_CONSTRAINT'}}})+'\n');
  if(m.method==='model/list')process.stdout.write(JSON.stringify({id:m.id,result:{data:[{model:'test-model',displayName:'Mock',defaultReasoningEffort:'high',supportedReasoningEfforts:[{reasoningEffort:'high'}],isDefault:true}],nextCursor:null}})+'\n');
  if(m.method==='account/rateLimits/read')process.stdout.write(JSON.stringify({id:m.id,result:{accountId:process.env.CODEX_STUB_ACCOUNT==='missing'?null:(process.env.CODEX_STUB_ACCOUNT||'acct-1'),ordinaryUsageAllowed:process.env.CODEX_STUB_DENY!=='1',rateLimits:{limitId:'test-model',normalModelSlug:'test-model',primary:{usedPercent:process.env.CODEX_STUB_DENY==='1'?100:0,resetsAt:Math.floor(Date.now()/1000)+3600,windowDurationMins:300}}}})+'\n');
 });
}else if(process.argv.includes('exec')||process.argv.includes('resume')){
 if(process.env.CODEX_STUB_MARKER)fs.writeFileSync(process.env.CODEX_STUB_MARKER,
   JSON.stringify(process.argv.slice(2)));
 if(process.env.CODEX_STUB_EMIT_WRITER==='1')console.log(JSON.stringify({type:'turn.failed',error:{message:'thread-store conflict: thread already has an active writer'}}));
 else if(process.env.CODEX_STUB_EMIT_LIMIT==='1')console.log(JSON.stringify({type:'turn.failed',error:{message:'Usage limit exceeded'}}));
 else console.log(JSON.stringify({type:'turn.completed'}));
 process.exitCode=Number(process.env.CODEX_STUB_EXIT||0);
}else{process.exitCode=2;}
'@ | Set-Content -LiteralPath $cli -Encoding utf8
    $shim=Join-Path $bin 'codex.cmd'
    @'
@echo off
node "%~dp0node_modules\@openai\codex\bin\codex.js" %*
exit /b %errorlevel%
'@ | Set-Content -LiteralPath $shim -Encoding ascii
    $repo=Join-Path $temp 'workspace'
    [void](New-Item -ItemType Directory -Path $repo -Force)
    & git -C $repo init --quiet -b feature
    if($LASTEXITCODE -ne 0){throw 'Failed to initialize isolated test repository.'}
    $repoRoot=([string](& git -C $repo rev-parse --show-toplevel)).Trim()
    $runtime=Publish-ImmutableRuntime -SourceDirectory $root -DestinationDirectory (Join-Path $temp 'runtimes') -RelativeFiles (Get-CodexRuntimeFiles)
    $fingerprint=$runtime.Fingerprint
    $workspaceHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes('codex-workspace-v1:acct-1'))).ToLowerInvariant()
    $expectedAccountIdentity='workspace-sha256:'+$workspaceHash
    $jobPath=Join-Path $temp 'job.json'
    $marker=Join-Path $temp 'executed.marker'
    $outcomePath=[IO.Path]::ChangeExtension($jobPath,'.result.json')
    $settingsDir=Join-Path $temp 'isolated-appdata'
    [void](New-Item -ItemType Directory -Path $settingsDir -Force)

    function Run-CodexStub([int]$expectedExit,[bool]$auto,[string]$activeAccount,[bool]$emitLimit,[bool]$writerConflict=$false,[string]$savedAccountId=$expectedAccountIdentity,[bool]$denyUsage=$false,[string]$executionMode='background') {
        if(Test-Path $marker){Remove-Item -LiteralPath $marker -Force}
        if(Test-Path $outcomePath){Remove-Item -LiteralPath $outcomePath -Force}
        [pscustomobject]@{
            sessionId='00000000-0000-0000-0000-000000000001'
            repo=$repoRoot;branch='feature';model='test-model';effort='high'
            access='read-only';message='Resume.';autoResume=$auto
            executionMode=$executionMode
            retryAttempt=0;accountId=$savedAccountId;runtimeFingerprint=$fingerprint
            log=(Join-Path $temp 'worker.log')
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jobPath
        $psi=[Diagnostics.ProcessStartInfo]::new()
        $psi.FileName=(Get-Command pwsh.exe -ErrorAction Stop).Source
        foreach($argument in @('-NoLogo','-NoProfile','-File',(Join-Path $runtime.Directory 'src/backend/Invoke-CodexJob.ps1'),'-JobFile',$jobPath)){
            [void]$psi.ArgumentList.Add($argument)
        }
        $psi.UseShellExecute=$false
        $psi.RedirectStandardOutput=$true
        $psi.RedirectStandardError=$true
        $psi.CreateNoWindow=$true
        $psi.Environment['PATH']="$bin;$env:PATH"
        $psi.Environment['LOCALAPPDATA']=$settingsDir
        $psi.Environment['CODEX_STUB_DENY']=if($denyUsage){'1'}else{'0'}
        $psi.Environment['CODEX_STUB_EXIT']=[string]$expectedExit
        $psi.Environment['CODEX_STUB_ACCOUNT']=$activeAccount
        $psi.Environment['CODEX_STUB_EMIT_LIMIT']=if($emitLimit){'1'}else{'0'}
        $psi.Environment['CODEX_STUB_EMIT_WRITER']=if($writerConflict){'1'}else{'0'}
        $psi.Environment['CODEX_STUB_MARKER']=$marker
        $proc=[Diagnostics.Process]::Start($psi)
        try{
            if(-not $proc.WaitForExit(20000)){
                try{$proc.Kill($true)}catch{}
                throw 'Isolated worker exceeded twenty seconds.'
            }
            $output=$proc.StandardOutput.ReadToEnd()
            $errors=$proc.StandardError.ReadToEnd()
            return [pscustomobject]@{ Exit=[int]$proc.ExitCode;Executed=(Test-Path $marker);Output=$output;Errors=$errors }
        }finally{$proc.Dispose()}
    }

    # Parent process holds a real named mutex; a separate scheduled worker
    # must decline the same session before invoking even a stub Codex command.
    $held=Enter-CodexSessionRun -SessionId '00000000-0000-0000-0000-000000000001'
    Require ($null -ne $held) 'Unable to establish the first scheduled writer lock.'
    try {
        $blocked=Run-CodexStub 0 $false 'acct-1' $false
        Require ($blocked.Exit -ne 0 -and -not $blocked.Executed) "Concurrent scheduled worker ran the same session: $($blocked.Output) $($blocked.Errors)"
        $blockedOutcome=Read-JobOutcome -Path $outcomePath
        Require ($blockedOutcome.status -eq 'blocked' -and $blockedOutcome.message -match 'already running|already.*active|duplicate execution') 'Overlapping session was not explicitly recorded as blocked.'
    } finally {
        $held.ReleaseMutex()
        $held.Dispose()
    }
    # A native Codex process may already have a writer without holding our
    # scheduler mutex. Its error must still be reported as a distinct block.
    $external=Run-CodexStub 1 $false 'acct-1' $false $true
    Require ($external.Exit -ne 0 -and $external.Executed) 'Mock native-writer conflict was not reproduced.'
    $externalOutcome=Read-JobOutcome -Path $outcomePath
    Require ($externalOutcome.status -eq 'blocked' -and $externalOutcome.message -match 'active writer') 'Native thread-store conflict was not distinguished from a generic failure.'

    # A single-execution run must still refuse a changed account.
    $changedOnce=Run-CodexStub 0 $false 'different-account' $false
    Require ($changedOnce.Exit -ne 0 -and -not $changedOnce.Executed) 'One-time job crossed workspace boundary.'
    Require ((Read-JobOutcome -Path $outcomePath).status -eq 'failed') 'One-time account mismatch was not recorded.'
    $missingBackend=Run-CodexStub 0 $false 'missing' $false
    Require ($missingBackend.Exit -ne 0 -and -not $missingBackend.Executed) 'Unidentified active workspace was allowed to run.'
    $missingSaved=Run-CodexStub 0 $false 'acct-1' $false $false ''
    Require ($missingSaved.Exit -ne 0 -and -not $missingSaved.Executed) 'Unbound saved job was allowed to run.'

    $ok=Run-CodexStub 0 $false 'acct-1' $false
    Require ($ok.Exit -eq 0 -and $ok.Executed) "Successful Codex execution must return zero: $($ok.Output) $($ok.Errors)"
    $outcome=Read-JobOutcome -Path $outcomePath
    Require ($outcome.status -eq "completed" -and $outcome.exitCode -eq 0) "Successful run must report completed outcome."
    # A terminal run uses the original conversation with a direct TUI and
    # no JSON pipeline. Its exit zero is not proof of completed work.
    Remove-Item -LiteralPath (Join-Path $temp 'job.jsonl') -Force
    $interactive=Run-CodexStub 0 $false 'acct-1' $false $false $expectedAccountIdentity $false 'terminal'
    Require ($interactive.Exit -eq 0 -and $interactive.Executed) "Native terminal Codex was not invoked: $($interactive.Output) $($interactive.Errors)"
    $interactiveArgs=@(Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json)
    Require ($interactiveArgs[0] -ceq 'resume' -and $interactiveArgs -ccontains '00000000-0000-0000-0000-000000000001' -and
        $interactiveArgs -ccontains 'Resume.' -and $interactiveArgs -ccontains 'read-only' -and $interactiveArgs -cnotcontains '--json') 'Terminal launch did not preserve session, instruction and permissions or used noninteractive output.'
    Require (-not (Test-Path -LiteralPath (Join-Path $temp 'job.jsonl'))) 'Native TUI must not be piped into JSONL output.'
    $outcome=Read-JobOutcome -Path $outcomePath
    Require ($outcome.status -eq 'finished' -and $outcome.exitCode -eq 0) 'Interactive exit must not be misreported as task completion.'
    $interactiveFailed=Run-CodexStub 17 $false 'acct-1' $false $false $expectedAccountIdentity $false 'terminal'
    $failedStatus=Read-JobOutcome -Path $outcomePath
    Require ($interactiveFailed.Exit -eq 17 -and $failedStatus.status -eq 'failed') "Interactive Codex failure was not preserved. Exit=$($interactiveFailed.Exit), status=$($failedStatus.status), output=$($interactiveFailed.Output), errors=$($interactiveFailed.Errors)"
    $terminalWrongAccount=Run-CodexStub 0 $false 'wrong-workspace' $false $false $expectedAccountIdentity $false 'terminal'
    Require ($terminalWrongAccount.Exit -ne 0 -and -not $terminalWrongAccount.Executed) 'Terminal mode bypassed the workspace identity check.'
    $terminalArgs=Get-CodexTaskArguments -Runner (Join-Path $temp 'src/backend/CodexRunJob.vbs') -JobFile $jobPath -ExecutionMode 'terminal'
    $backgroundArgs=Get-CodexTaskArguments -Runner (Join-Path $temp 'src/backend/CodexRunJob.vbs') -JobFile $jobPath
    Require ($terminalArgs.EndsWith(' terminal') -and -not $backgroundArgs.EndsWith(' terminal')) 'Terminal visibility did not remain opt-in per task.'
    # Child processes inherit a different LOCALAPPDATA. Events and outcomes
    # must live beside the immutable job payload, not there.
    $backToBackground=Run-CodexStub 0 $false 'acct-1' $false
    Require ($backToBackground.Exit -eq 0 -and $backToBackground.Executed) 'Legacy background launch regressed.'
    $expectedEvents=Join-Path $temp 'job.jsonl'
    $wrongEvents=Join-Path (Join-Path $settingsDir 'CodexResumeScheduler') 'job.jsonl'
    Require (Test-Path -LiteralPath $expectedEvents -PathType Leaf) 'Worker wrote execution events outside its job directory.'
    Require (-not (Test-Path -LiteralPath $wrongEvents)) 'Worker leaked events into the inherited profile directory.'
    $failed=Run-CodexStub 17 $false 'acct-1' $false
    Require ($failed.Exit -eq 17 -and $failed.Executed) "CLI exit 17 must be preserved, not reported as success: $($failed.Output) $($failed.Errors)"
    $outcome=Read-JobOutcome -Path $outcomePath
    Require ($outcome.status -eq "failed" -and $outcome.exitCode -eq 17 -and -not $outcome.nextJob) "Failed Codex execution must record its actual failure with no follow-up."
    # A legacy payload with autoResume=true must not schedule another job
    # using the new worker, even when Codex emits a usage-limit error.
    $legacy=Run-CodexStub 17 $true 'acct-1' $true
    Require ($legacy.Exit -eq 17 -and $legacy.Executed) "Legacy retry flag must not alter execution."
    $outcome=Read-JobOutcome -Path $outcomePath
    Require ($outcome.status -eq 'failed' -and -not $outcome.nextJob) 'A usage-limit failure unexpectedly registered another run.'
    Require (@(Get-ChildItem -LiteralPath $temp -Filter 'CodexResume-*.json' -File).Count -eq 0) 'A hidden follow-up payload was written.'
    # Verified quota denial blocks the run before calling Codex, but never
    # schedules a retry. (All account checks must still apply.)
    $quotaBlocked=Run-CodexStub 0 $true 'acct-1' $false $false $expectedAccountIdentity $true
    Require ($quotaBlocked.Exit -ne 0 -and -not $quotaBlocked.Executed) 'Quota denial invoked Codex despite unavailable capacity.'
    $outcome=Read-JobOutcome -Path $outcomePath
    Require ($outcome.status -eq 'blocked' -and -not $outcome.nextJob) 'Quota denial must record a blocked one-time result.'
    $stale=Run-CodexStub 0 $true 'acct-1' $true
    Require ($stale.Exit -eq 0 -and $stale.Executed) "Success must override stale limit-like events: $($stale.Output) $($stale.Errors)"
    $outcome=Read-JobOutcome -Path $outcomePath
    Require ($outcome.status -eq "completed") "Stale error events must not cause deferred outcome on success."
    $changed=Run-CodexStub 0 $true 'different-account' $false
    Require ($changed.Exit -ne 0 -and -not $changed.Executed) "Wrong account must stop before invoking Codex: $($changed.Output) $($changed.Errors)"
    $outcome=Read-JobOutcome -Path $outcomePath
    Require ($outcome.status -eq "failed") "Account mismatch must be recorded as a failed preflight."
    # Read-only conversation checks distinguish a recoverable quota error
    # from an inaccessible thread. Actual child execution is covered by the
    # isolated parent-to-child lifecycle test.
    $probePath=$env:PATH
    try {
        $env:PATH="$bin;$probePath"
        $env:CODEX_STUB_THREAD_MISSING='0'
        Assert-CodexConversationAvailable -SessionId '00000000-0000-0000-0000-000000000001'
        $env:CODEX_STUB_THREAD_MISSING='1'
        $missingThreadRefused=$false
        try{Assert-CodexConversationAvailable -SessionId '00000000-0000-0000-0000-000000000001'}catch{$missingThreadRefused=$true}
        Require $missingThreadRefused 'Missing conversation was treated as readable.'
    } finally {
        $env:PATH=$probePath
        Remove-Item Env:CODEX_STUB_THREAD_MISSING -ErrorAction SilentlyContinue
    }

    # A pinned runtime must fail closed after an existing dependency changes.
    Set-Content -LiteralPath (Join-Path $runtime.Directory 'src/backend/CodexUsage.js') -Value 'tampered'
    $tampered=Run-CodexStub 0 $false 'acct-1' $false
    Require ($tampered.Exit -ne 0 -and -not $tampered.Executed) "Modified scheduled runtime must fail before Codex: $($tampered.Output) $($tampered.Errors)"
    $outcome=Read-JobOutcome -Path $outcomePath
    Require ($outcome.status -eq "failed") "Fingerprint failure must persist a failed outcome."
    Write-Host 'Pinned worker: one execution, quota block, exit 17, legacy retry ignored, identity and tampering PASS.'
}finally{
    if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
