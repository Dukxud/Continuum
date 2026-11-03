'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'..');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const worker=read('CodexRunEngine.ps1'),actions=read('CodexUiActions.ps1'),forms=read('CodexUiForms.ps1');
test('one schedule produces one execution with no retry or helper',()=>{
 assert.doesNotMatch(worker,/Schedule-LimitRetry|CodexRetry|\$auto\b|\$nextJob\b|retryAttempt|autoResume/);
 assert.doesNotMatch(actions,/autoResumeCheck|autoResume\s*=|retryAttempt\s*=/);
 assert.doesNotMatch(forms,/autoResumeCheck|Retry if Codex/);
 assert.ok(!fs.existsSync(path.join(root,'CodexRetry.js')),'Legacy retry helper is still shipped');
 assert.match(worker,/\$result = \$LASTEXITCODE/);
 assert.match(worker,/Set-CodexRunOutcome -JobFile \$JobFile -Status 'failed'/);
 assert.match(worker,/return \[int\]\$result/);
});
test('worker still preserves pinned runtime and workspace safeguards',()=>{
 for(const phrase of ['Get-CodexRuntimeFiles','Assert-RuntimeFingerprint',
 'Enter-CodexSessionRun','Test-CanonicalWorkspaceIdentity','Read-UsageState',
 'Assert-ModelEffortSupported','Read-CodexModelCatalog']){
  assert.ok(worker.includes(phrase),phrase+' was unexpectedly lost');
 }
 assert.match(worker,/if \(\$state\.canAttempt -eq \$false\)/);
 assert.match(worker,/Set-CodexRunOutcome -JobFile \$JobFile -Status 'blocked'/);
 assert.match(actions,/Test-CanonicalWorkspaceIdentity \$accountId/);
 assert.match(actions,/Publish-ImmutableRuntime/);
 assert.match(actions,/Remove-OneTimeTask -Name \$name -OnlyBeforeStart/);
});
test('new jobs omit retry fields and retain explicit behavior',()=>{
 assert.match(actions,/sessionId=\$sessionId; repo=\$root; branch=\$branch/);
 assert.match(actions,/model=\$model; effort=\$effort; access=\$access; message=\$message/);
 assert.match(actions,/accountId=\$accountId/);
 assert.match(actions,/runtimeFingerprint=\$runtime\.Fingerprint/);
 assert.doesNotMatch(actions,/autoResume|retryAttempt/);
 const runtime=worker.match(/function Get-CodexRuntimeFiles\s*\{([\s\S]*?)\n\}/)?.[1];
 assert.ok(runtime);
 assert.ok(!runtime.includes('CodexRetry.js'));
 assert.ok(runtime.includes('CodexUsage.js'));
});
test('release and worker manifests exclude retries without losing scheduling dependencies',()=>{
 const release=read('scripts/Package-CodexScheduler.ps1');
 assert.match(release,/'CodexScheduleTime\.ps1'/);
 assert.match(release,/'CodexUsage\.js'/);
 assert.doesNotMatch(release,/CodexRetry\.js/);
 assert.match(worker,/'CodexUsage\.js'/);
 assert.match(worker,/Set-CodexRunOutcome -JobFile \$JobFile -Status 'blocked'/);
 assert.match(worker,/Set-CodexRunOutcome -JobFile \$JobFile -Status 'failed'/);
});
