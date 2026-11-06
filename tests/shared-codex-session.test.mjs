import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { SharedSessionHost, locationFor } from '../components/SharedCodexSession/host.mjs';
import { connectToSession } from '../components/SharedCodexSession/client.mjs';
import { validateUserResponse } from '../components/SharedCodexSession/protocol.mjs';

const thread = '11111111-2222-3333-4444-555555555555';
const jobName = 'CodexResume-20261105-1737-8fea70e0';
const fake = resolve('tests/shared-codex-fake-app-server.mjs');
const sleep = ms => new Promise(done => setTimeout(done, ms));
const waitFor = async predicate => {
  for (let i=0; i<100; i++) { if (predicate()) return; await sleep(10); }
  throw new Error('Timed out waiting for Codex test event');
};

test('one App Server process, two viewers, command approval and user question', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'continuum-shared-'));
  const host = new SharedSessionHost({
    job: { sessionId: thread, repo: process.cwd(), message: 'Continue.', model: 'test', effort: 'medium', access: 'workspace-write' },
    jobName, appDir: dir, codexEntry: fake,
    spawnServer: () => spawn(process.execPath, [fake],
      { stdio: ['pipe','pipe','pipe'], env: { ...process.env, FAKE_THREAD_ID: thread } }),
  });
  t.after(async () => { await host.close(); await rm(dir, { recursive: true, force: true }); });
  const running = host.begin();
  await waitFor(() => host.pending.has('100'));
  assert.equal(host.status, 'needs-input', 'Immediate approval must retain needs-input status');
  const descriptor = locationFor(dir, jobName).descriptor;
  assert.ok((await readFile(descriptor, 'utf8')).includes('secret'));
  const seen = [];
  const first = await connectToSession(descriptor, event => seen.push(event));
  const second = await connectToSession(descriptor, event => seen.push(event));
  await waitFor(() => host.sockets.size === 2);
  assert.equal(host.sockets.size, 2);
  first.write(JSON.stringify({ action: 'answer', id: '100', result: { decision: 'accept' } }) + '\n');
  await waitFor(() => host.pending.has('101'));
  // A second viewer cannot approve the already-consumed request.
  second.write(JSON.stringify({ action: 'answer', id: '100', result: { decision: 'accept' } }) + '\n');
  await waitFor(() => seen.some(event => event.action === 'error' && /expired/.test(event.message)));
  second.write(JSON.stringify({ action: 'answer', id: '101', result: { answers: { choice: { answers: ['Yes'] } } } }) + '\n');
  assert.equal(await running, 'completed');
  assert.equal(host.pending.size, 0);
  assert.equal(host.events.some(event => event.text === 'Visible stream text'), true);
  assert.equal(host.completed, true);
  first.end(); second.end();
});
test('file edits and unknown network requests never receive blind approval', () => {
  const file = { method:'item/fileChange/requestApproval', params: { proposedChanges:[], previewComplete:false } };
  assert.throws(() => validateUserResponse(file, { decision:'accept' }));
  assert.deepEqual(validateUserResponse(file, { decision:'decline' }), { decision:'decline' });
  file.params.proposedChanges = [{ path:'src/test.dart', kind:'update', diff:'@@ -1 +1 @@' }];
  assert.throws(() => validateUserResponse(file, { decision:'accept' }), 'Incomplete diff must not be approved');
  file.params.previewComplete = true;
  assert.deepEqual(validateUserResponse(file, { decision:'accept' }), { decision:'accept' });
  const command = { method:'item/commandExecution/requestApproval', params: {} };
  assert.throws(() => validateUserResponse(command, { decision:'accept' }));
  command.params.networkApprovalContext = { host:'example.test', protocol:'https' };
  assert.deepEqual(validateUserResponse(command, { decision:'accept' }), { decision:'accept' });
});

test('both Codex question method variants require exact question IDs', () => {
  for (const method of ['item/tool/requestUserInput','tool/requestUserInput']) {
    const req = { method, params: { questions: [{ id: 'valid' }] } };
    assert.deepEqual(validateUserResponse(req,
      { answers: { valid: { answers: ['Yes'] } } }),
      { answers: { valid: { answers: ['Yes'] } } });
    assert.throws(() => validateUserResponse(req,
      { answers: { arbitrary: { answers: ['Yes'] } } }));
  }
});

test('reject implicit approvals, unknown questions and permission escalation', () => {
  const req = { method: 'item/commandExecution/requestApproval' };
  assert.throws(() => validateUserResponse(req, { decision: 'accept', unsafe: true }));
  assert.throws(() => validateUserResponse(req, { decision: 'acceptWithExecpolicyAmendment' }));
  assert.deepEqual(validateUserResponse(req, { decision: 'decline' }), { decision: 'decline' });
  assert.throws(() => validateUserResponse(
    { method:'item/tool/requestUserInput', params: { questions: [{ id:'valid' }] } },
    { answers: { other: { answers: ['wrong'] } } }));
  assert.throws(() => validateUserResponse(
    { method:'item/permissions/requestApproval' }, { permissions: { network: 'all' } }));
});


test('reject approvals scoped to another active turn', () => {
  const host = new SharedSessionHost({
    job: { sessionId: thread, repo: process.cwd(), message: 'Continue.' },
    jobName, appDir: tmpdir(), codexEntry: fake,
  });
  host.turnId = 'active-turn';
  host.onAppMessage({ id: 45, method: 'item/commandExecution/requestApproval',
    params: { threadId: thread, turnId: 'stale-turn', command: 'echo unsafe' } });
  assert.equal(host.status, 'failed');
  assert.equal(host.pending.size, 0);
});

test('reject duplicated server request IDs and unrelated resolution notifications', () => {
  const host = new SharedSessionHost({
    job: { sessionId: thread, repo: process.cwd(), message: 'Continue.' },
    jobName, appDir: tmpdir(), codexEntry: fake,
  });
  host.turnId = 'active-turn';
  const request = { id: 45, method: 'item/commandExecution/requestApproval',
    params: { threadId: thread, turnId: 'active-turn', command: 'echo safe' } };
  host.onAppMessage(request);
  assert.equal(host.pending.size, 1);
  host.onAppMessage({ method: 'serverRequest/resolved',
    params: { threadId: 'wrong-thread', requestId: 45 } });
  assert.equal(host.status, 'failed');
  assert.equal(host.pending.size, 0);

  const another = new SharedSessionHost({
    job: { sessionId: thread, repo: process.cwd(), message: 'Continue.' },
    jobName, appDir: tmpdir(), codexEntry: fake,
  });
  another.turnId = 'active-turn';
  another.onAppMessage(request);
  another.onAppMessage(request);
  assert.equal(another.status, 'failed');
  assert.equal(another.pending.size, 0);
});

test('pre-turn approvals are buffered until their turn ID is verified', () => {
  const host = new SharedSessionHost({
    job: { sessionId: thread, repo: process.cwd(), message: 'Continue.' },
    jobName, appDir: tmpdir(), codexEntry: fake,
  });
  const request = { id: 55, method: 'item/commandExecution/requestApproval',
    params: { threadId: thread, turnId: 'wrong-turn', command: 'echo invalid' } };
  host.onAppMessage(request);
  assert.equal(host.pending.size, 0);
  assert.equal(host.earlyRequests.length, 1);
  host.turnId = 'actual-turn';
  for (const early of host.earlyRequests.splice(0)) host.onAppMessage(early);
  assert.equal(host.status, 'failed');
  assert.equal(host.pending.size, 0);
});
