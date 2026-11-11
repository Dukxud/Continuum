'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'..');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const worker=read('src/backend/CodexRunEngine.ps1');
const continuation=read('src/backend/CodexQuotaContinuation.ps1');
const winforms=read('legacy/winforms/CodexUiActions.ps1');
const forms=read('legacy/winforms/CodexUiForms.ps1');
const bridge=read('flutter_port/windows_bridge.ps1');

test('legacy WinForms and old job files remain one-shot',()=>{
 assert.doesNotMatch(winforms,/autoResumeCheck|continuationPolicy|retryAttempt\s*=/);
 assert.doesNotMatch(forms,/autoResumeCheck|Retry if Codex/);
 assert.doesNotMatch(continuation,/\$Job\.autoResume\b/);
 assert.match(continuation,/\$Job\.continuationPolicy/);
 assert.match(continuation,/mode -cne 'quota-only'/);
 assert.match(continuation,/maxContinuations -cne '3'/);
 assert.doesNotMatch(continuation,/Start-Sleep|while\s*\(/);
 assert.ok(!fs.existsSync(path.join(root,'CodexRetry.js')));
});

test('post-run continuation only follows actual quota event and verified reset',()=>{
 assert.match(worker,/Test-CodexTerminalQuotaFailure -EventsPath \$events/);
 assert.match(worker,/Try-DeferCodexQuotaJob/);
 assert.match(continuation,/Get-VerifiedQuotaContinuationTime/);
 assert.match(continuation,/recommendationKind -cne 'exhausted-window'/);
 assert.match(continuation,/selectionVerified -ne \$true/);
 assert.match(continuation,/\$Quota\.canAttempt -ne \$false/);
 assert.match(continuation,/\$reset\.AddMinutes\(1\)/);
 assert.match(worker,/\$result = \$LASTEXITCODE/);
 assert.match(worker,/Set-CodexRunOutcome -JobFile \$JobFile -Status 'failed'/);
});

test('pinned worker and task lifecycle still verify identity and single-writer lock',()=>{
 for(const phrase of ['Get-CodexRuntimeFiles','Assert-RuntimeFingerprint',
 'Enter-CodexSessionRun','Test-CanonicalWorkspaceIdentity','Read-UsageState',
 'Assert-ModelEffortSupported','Read-CodexModelCatalog']){
  assert.ok(worker.includes(phrase),phrase+' was unexpectedly lost');
 }
 assert.match(worker,/if \(\$state\.canAttempt -ne \$true\)/);
 assert.match(worker,/Set-CodexRunOutcome -JobFile \$JobFile -Status 'blocked'/);
 assert.match(winforms,/Test-CanonicalWorkspaceIdentity \$accountId/);
 assert.match(winforms,/Publish-ImmutableRuntime/);
 assert.match(winforms,/Remove-OneTimeTask -Name \$name -OnlyBeforeStart/);
 assert.match(continuation,/Assert-NoPendingCodexSessionSibling/);
 assert.match(continuation,/Get-RegisteredCodexQuotaContinuation/);
});

test('only newly created Flutter jobs carry a versioned opt-in',()=>{
 assert.match(bridge,/\$request\.autoResumeOnLimit -isnot \[bool\]/);
 assert.match(bridge,/continuationPolicy=\$policy;retryAttempt=0/);
 assert.match(bridge,/mode='quota-only';maxContinuations=3/);
 assert.match(continuation,/\$attempt -ge 3/);
 assert.match(continuation,/Set-CodexRunOutcome|SettingsStore\\Write-JsonSettings/);
});

test('both distribution manifests include the new pinned worker source',()=>{
 const release=read('scripts/Package-CodexScheduler.ps1');
 const flutter=read('flutter_port/Build-WindowsPreview.ps1');
 const runtime=worker.match(/function Get-CodexRuntimeFiles\s*\{([\s\S]*?)\n\}/)?.[1];
 assert.ok(runtime);
 assert.match(runtime,/'src\/backend\/CodexQuotaContinuation\.ps1'/);
 assert.match(release,/'src\/backend\/CodexQuotaContinuation\.ps1'/);
 assert.match(flutter,/'src\/backend\/CodexQuotaContinuation\.ps1'/);
 assert.match(runtime,/'src\/backend\/CodexUsage\.js'/);
});
