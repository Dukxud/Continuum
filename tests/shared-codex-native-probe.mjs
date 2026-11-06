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
const runId = 'BP199';
const jobName = 'CodexResume-20261105-2211-a11ce999';
const deadline = 90000;
const seen = [];
const print = message => process.stdout.write('[' + runId + '] ' + message + '\n');

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

    const outcome = await Promise.race([
      completion,
      delay(deadline).then(() => { throw new Error('Native turn timed out'); }),
    ]);
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
