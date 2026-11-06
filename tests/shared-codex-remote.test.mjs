import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { AppServerProtocol } from '../components/SharedCodexSession/protocol.mjs';
import { openRemoteProtocol, nativeTuiArguments, REMOTE_TOKEN_ENV } from '../components/SharedCodexSession/remote.mjs';
import { SharedSessionHost, locationFor } from '../components/SharedCodexSession/host.mjs';
import { connectToSession } from '../components/SharedCodexSession/client.mjs';

const sessionId = '11111111-2222-3333-4444-555555555555';
const jobName = 'CodexResume-20261105-2245-abc123ef';
const fakeServer = resolve('tests/shared-codex-fake-app-server.mjs');
const token = 'a'.repeat(64);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function waitFor(predicate) {
  for (let i = 0; i < 150; i++) {
    if (predicate()) return;
    await sleep(10);
  }
  throw new Error('Mock shared owner timed out');
}

class FakeSocket extends EventTarget {
  constructor(endpoint, options) {
    super();
    this.endpoint = endpoint;
    this.options = options;
    this.readyState = 0;
    this.sent = [];
    queueMicrotask(() => {
      this.readyState = 1;
      this.dispatchEvent(new Event('open'));
    });
  }
  send(raw) {
    this.sent.push(JSON.parse(raw));
    const request = this.sent.at(-1);
    if (Object.hasOwn(request, 'id')) {
      const event = new Event('message');
      event.data = JSON.stringify({ id: request.id,
        result: { method: request.method, params: request.params } });
      queueMicrotask(() => this.dispatchEvent(event));
    }
  }
  close() {
    if (this.readyState === 3) return;
    this.readyState = 3;
    this.dispatchEvent(new Event('close'));
  }
}

test('authenticated loopback protocol sends framed JSON-RPC without starting a second server', async () => {
  let socket;
  const connection = await openRemoteProtocol({
    endpoint: 'ws://127.0.0.1:43129', token,
    child: { exitCode: null, signalCode: null },
    makeSocket: (endpoint, options) => {
      socket = new FakeSocket(endpoint, options);
      return socket;
    },
    attempts: 1,
  });
  try {
    assert.equal(socket.options.headers.Authorization, 'Bearer ' + token);
    assert.equal(socket.endpoint, 'ws://127.0.0.1:43129');
    const result = await connection.protocol.request('thread/resume', { threadId: sessionId });
    assert.deepEqual(result, { method: 'thread/resume', params: { threadId: sessionId } });
    assert.equal(socket.sent.length, 1);
  } finally {
    connection.close();
  }
});

test('remote policy refuses unauthenticated and non-loopback endpoints', async () => {
  await assert.rejects(openRemoteProtocol({
    endpoint: 'ws://0.0.0.0:43129', token,
    child: { exitCode: null, signalCode: null },
  }));
  await assert.rejects(openRemoteProtocol({
    endpoint: 'ws://127.0.0.1:43129', token: 'short',
    child: { exitCode: null, signalCode: null },
  }));
  assert.throws(() => nativeTuiArguments('codex.js', 'ws://example.com:4500', sessionId));
  assert.deepEqual(nativeTuiArguments('codex.js', 'ws://127.0.0.1:4500', sessionId),
    ['codex.js', '--remote', 'ws://127.0.0.1:4500',
      '--remote-auth-token-env', REMOTE_TOKEN_ENV, 'resume', sessionId]);
});

test('native credentials are private, require active owner, and never fork the thread', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'continuum-remote-mock-'));
  let args;
  const host = new SharedSessionHost({
    job: { sessionId, repo: process.cwd(), message: 'Continue.', access: 'workspace-write' },
    jobName, appDir: directory, codexEntry: fakeServer, remote: true,
    reservePort: async () => 45621,
    spawnServer: values => {
      args = values;
      return spawn(process.execPath, [fakeServer], { stdio: ['pipe', 'pipe', 'pipe'],
        env: { ...process.env, FAKE_THREAD_ID: sessionId } });
    },
    connectRemote: async ({ endpoint, token: secret, child }) => {
      assert.equal(endpoint, 'ws://127.0.0.1:45621');
      assert.match(secret, /^[a-f0-9]{64}$/);
      return { protocol: new AppServerProtocol(child), close() {} };
    },
  });
  t.after(async () => {
    await host.close();
    await rm(directory, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  });
  const running = host.begin();
  running.catch(() => {});
  await waitFor(() => host.pending.has('100'));
  assert.equal(host.status, 'needs-input');
  const descriptor = locationFor(directory, jobName).descriptor;
  const disk = JSON.parse(await readFile(descriptor, 'utf8'));
  assert.equal(disk.token, undefined);
  assert.equal(disk.remoteToken, undefined);
  assert.equal(host.snapshot().token, undefined);
  assert.equal(host.snapshot().remoteEndpoint, undefined);
  assert.deepEqual(args.slice(0, 4),
    ['--listen', 'ws://127.0.0.1:45621', '--ws-auth', 'capability-token']);
  const events = [];
  const viewer = await connectToSession(descriptor, message => events.push(message));
  await waitFor(() => host.sockets.size === 1);
  viewer.write(JSON.stringify({ action: 'native-attach' }) + '\n');
  await waitFor(() => events.some(message => message.action === 'native-credentials'));
  const creds = events.find(message => message.action === 'native-credentials');
  assert.equal(creds.threadId, sessionId);
  assert.equal(creds.endpoint, 'ws://127.0.0.1:45621');
  assert.equal(args[5], createHash('sha256').update(creds.token).digest('hex'));
  assert.equal(events.some(event => event.action === 'snapshot' && event.token), false);
  viewer.write(JSON.stringify({ action: 'answer', id: '100', result: { decision: 'accept' } }) + '\n');
  await waitFor(() => host.pending.has('101'));
  viewer.write(JSON.stringify({ action: 'answer', id: '101',
    result: { answers: { choice: { answers: ['Yes'] } } } }) + '\n');
  assert.equal(await running, 'completed');
  viewer.write(JSON.stringify({ action: 'native-attach' }) + '\n');
  await waitFor(() => events.some(event => event.action === 'error' &&
    /requires a running shared owner/.test(event.message)));
  viewer.end();
});
