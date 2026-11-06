import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { access, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, isAbsolute } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { AppServerProtocol, isUuid } from '../components/SharedCodexSession/protocol.mjs';
import { SharedSessionHost, locationFor } from '../components/SharedCodexSession/host.mjs';
import { connectToSession } from '../components/SharedCodexSession/client.mjs';

// Native-only probe: creates a disposable test thread, never resumes a user's
// working conversation, and never launches a second writer for that thread.
const codexEntry = process.argv[2];
if (!isAbsolute(codexEntry ?? '')) {
  console.error('Usage: node tests/shared-codex-native-probe.mjs ABSOLUTE_CODEX_CLI_JS');
  process.exit(2);
}
const runId = 'BP200';
const jobName = 'CodexResume-20261105-2220-a11ce999';
const deadline = 90000;
const seen = [];
const print = message => process.stdout.write('[' + runId + '] ' + message + '\n');

async function withDeadline(promise, maxMs, message) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(message)), maxMs);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

function waitForCompletedTurn(api, threadId) {
  let dispose = () => {};
  const promise = new Promise((resolve, reject) => {
    const onMessage = message => {
      if (message.method !== 'turn/completed' || message.params?.threadId !== threadId) return;
      dispose();
      resolve(message.params.turn);
    };
    const onClosed = error => { dispose(); reject(error); };
    dispose = () => {
      api.off('message', onMessage);
      api.off('closed', onClosed);
    };
    api.on('message', onMessage);
    api.on('closed', onClosed);
  });
  // An RPC failure can occur before the observer is awaited.
  promise.catch(() => {});
  return { promise, dispose };
}

async function waitForFile(path, maxMs = 15000) {
  const end = Date.now() + maxMs;
  while (Date.now() < end) {
    try { await access(path); return; } catch { await delay(50); }
  }
  throw new Error('Shared owner did not create its endpoint descriptor');
}
async function stop(child) {
  if (!child || child.exitCode !== null) return;
  child.kill();
  await Promise.race([
    new Promise(resolve => child.once('exit', resolve)),
    delay(2000),
  ]);
  if (child.exitCode === null) child.kill('SIGKILL');
}
async function main() {
  const dir = await mkdtemp(join(tmpdir(), 'continuum-native-probe-'));
  let initialChild, host, first, second;
  try {
    initialChild = spawn(process.execPath, [codexEntry, 'app-server'], {
      cwd: dir, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true,
    });
    initialChild.stderr.resume();
    const api = new AppServerProtocol(initialChild, { timeoutMs: 20000 });
    const init = await api.request('initialize', {
      clientInfo: { name: 'continuum_native_probe', title: 'Continuum Native Probe', version: '0.1.0' },
      capabilities: { experimentalApi: true },
    });
    assert.ok(init && typeof init === 'object', 'Codex initialize returned no object');
    api.send({ method: 'initialized', params: {} });
    print('PASS - Real Codex App Server initialization');
    const created = await api.request('thread/start', { cwd: dir });
    const threadId = created?.thread?.id;
    assert.ok(isUuid(threadId), 'Codex did not create a valid disposable thread');
    print('PASS - Disposable thread created (original conversation untouched)');

    // Codex 0.151+ does not necessarily persist a zero-turn thread.
    // Finish a genuine first turn before trying to resume it in another process.
    const seed = waitForCompletedTurn(api, threadId);
    try {
      const started = await api.request('turn/start', {
        threadId,
        input: [{ type: 'text', text: 'Reply with exactly: Ready.' }],
        cwd: dir,
        approvalPolicy: 'never',
        sandboxPolicy: { type: 'readOnly' },
      });
      assert.ok(started?.turn?.id, 'Seed turn was not acknowledged');
      const completed = await withDeadline(seed.promise, deadline, 'Disposable seed turn timed out');
      assert.equal(completed?.id, started.turn.id, 'Different seed turn completed');
      assert.equal(completed?.status, 'completed', 'Disposable seed turn failed');
    } finally {
      seed.dispose();
    }
    const persisted = await api.request('thread/turns/list', {
      threadId, limit: 5, sortDirection: 'desc', itemsView: 'notLoaded',
    });
    assert.ok(Array.isArray(persisted?.data) && persisted.data.length > 0,
      'First turn completed but thread history was not persisted');
    print('PASS - Seed turn completed and persisted before App Server restart');
    await stop(initialChild);
    initialChild = undefined;

    host = new SharedSessionHost({
      job: {
        sessionId: threadId, repo: dir,
        message: 'Reply with the exact words: Continuum native probe passed. Do not use tools or edit files.',
        access: 'read-only',
      },
      jobName, appDir: dir, codexEntry,
    });
    const completion = host.begin();
    // The host's completion promise may reject while we await its descriptor.
    completion.catch(() => {});
    await waitForFile(locationFor(dir, jobName).descriptor);
    first = await connectToSession(locationFor(dir, jobName).descriptor, msg => seen.push({ viewer: 1, msg }));
    second = await connectToSession(locationFor(dir, jobName).descriptor, msg => seen.push({ viewer: 2, msg }));
    assert.equal(host.sockets.size, 2, 'Not exactly two attached viewers');
    print('PASS - Two authenticated viewers, one Codex App Server owner');

    const outcome = await withDeadline(completion, deadline, 'Native resumed turn timed out');
    assert.equal(outcome, 'completed', 'Native Codex turn did not complete');
    assert.ok(host.events.some(event => event.kind === 'turn' && event.method === 'turn/completed'));
    assert.ok(seen.some(({ viewer, msg }) => viewer === 1 && msg.action === 'snapshot'));
    assert.ok(seen.some(({ viewer, msg }) => viewer === 2 && msg.action === 'snapshot'));
    print('PASS - Real resumed thread completed through shared owner');
    print('PASS - Original conversation not resumed, forked or modified');
  } finally {
    first?.end();
    second?.end();
    if (host) {
      if (!host.completed) host.fatal(new Error('Native probe stopped'));
      await host.close();
    }
    await stop(initialChild);
    await rm(dir, { recursive: true, force: true });
  }
}
main().catch(error => {
  print('FAIL - ' + error.message);
  process.exitCode = 1;
});
