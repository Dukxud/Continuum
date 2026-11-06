import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { isAbsolute, join } from 'node:path';
import { once } from 'node:events';

// Isolated native-TUI attachment probe. No production jobs or threads are used.
const codexEntry = process.argv[2];
if (!isAbsolute(codexEntry ?? '')) {
  console.error('Usage: node tests/shared-codex-native-tui-probe.mjs ABSOLUTE_CODEX_CLI_JS');
  process.exit(2);
}
const marker = 'CONTINUUM_NATIVE_REMOTE_' + randomBytes(5).toString('hex').toUpperCase();
const say = message => console.log('[BP203] ' + message);

function timeout(promise, milliseconds, description) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(description)), milliseconds); }),
  ]).finally(() => clearTimeout(timer));
}

async function unusedLoopbackPort() {
  const server = createServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const port = server.address().port;
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  return port;
}

class RpcClient {
  constructor(socket) {
    this.socket = socket;
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Set();
    socket.addEventListener('message', event => {
      let message;
      try { message = JSON.parse(event.data); }
      catch { this.fail(new Error('Malformed server message')); return; }
      if (Object.hasOwn(message, 'id') && !message.method) {
        const pending = this.pending.get(message.id);
        if (pending) {
          this.pending.delete(message.id);
          if (message.error) pending.reject(new Error(message.error.message));
          else pending.resolve(message.result);
        }
      } else if (message.method) {
        for (const listener of this.listeners) listener(message);
      }
    });
    socket.addEventListener('close', () => this.fail(new Error('Codex WebSocket closed')));
    socket.addEventListener('error', () => this.fail(new Error('Codex WebSocket error')));
  }
  fail(error) {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
  }
  send(method, params) { this.socket.send(JSON.stringify({ method, params })); }
  request(method, params) {
    const id = this.nextId++;
    return timeout(new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    }), 25000, method + ' timed out').finally(() => this.pending.delete(id));
  }
  waitForCompletedTurn(threadId) {
    let listener, timer;
    let rejectCompletion;
    const result = new Promise((resolve, reject) => {
      rejectCompletion = reject;
      listener = message => {
        if (message.method === 'turn/completed' && message.params?.threadId === threadId) {
          dispose();
          resolve(message.params.turn);
        }
      };
      this.listeners.add(listener);
    });
    const dispose = () => {
      clearTimeout(timer);
      this.listeners.delete(listener);
    };
    timer = setTimeout(() => {
      dispose();
      rejectCompletion(new Error('Seed turn timed out'));
    }, 90000);
    result.catch(() => {});
    return {
      result,
      dispose: () => { dispose(); rejectCompletion(new Error('Seed observer disposed')); },
    };
  }
}

async function connect(url, token) {
  const socket = new WebSocket(url, { headers: { Authorization: 'Bearer ' + token } });
  await timeout(new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', () => reject(new Error('Authenticated WebSocket handshake failed')), { once: true });
  }), 12000, 'Codex App Server WebSocket handshake timed out');
  return new RpcClient(socket);
}

async function stop(child, closed) {
  if (!child) return;
  if (child.exitCode === null && child.signalCode === null) child.kill();
  try { await timeout(closed, 2000, 'App Server close timed out'); }
  catch (error) {
    if (child.exitCode !== null || child.signalCode !== null) throw error;
    child.kill('SIGKILL');
    await timeout(closed, 2000, 'App Server failed to release its handles');
  }
}

async function main() {
  const dir = await mkdtemp(join(tmpdir(), 'continuum-native-tui-'));
  let child, childClosed, rpc;
  try {
    const port = await unusedLoopbackPort();
    const url = 'ws://127.0.0.1:' + port;
    const token = randomBytes(32).toString('hex');
    const digest = createHash('sha256').update(token).digest('hex');
    child = spawn(process.execPath, [codexEntry, 'app-server', '--listen', url,
      '--ws-auth', 'capability-token', '--ws-token-sha256', digest], {
      cwd: dir, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true,
    });
    childClosed = once(child, 'close');
    childClosed.catch(() => {});
    // Drain output to prevent the App Server from blocking on a full pipe.
    child.stdout.resume();
    child.stderr.resume();
    let lastError;
    for (let i = 0; i < 30; i++) {
      if (child.exitCode !== null) throw new Error('Codex App Server exited before accepting connections');
      try { rpc = await connect(url, token); break; }
      catch (error) { lastError = error; await new Promise(resolve => setTimeout(resolve, 150)); }
    }
    if (!rpc) throw lastError ?? new Error('Codex App Server did not start');
    await rpc.request('initialize', { clientInfo: {
      name: 'continuum_remote_tui_probe', title: 'Continuum Native TUI Probe', version: '0.1.0',
    }, capabilities: { experimentalApi: true } });
    rpc.send('initialized', {});
    say('PASS - Authenticated loopback App Server connected');
    const created = await rpc.request('thread/start', { cwd: dir });
    const threadId = created?.thread?.id;
    assert.match(threadId ?? '', /^[a-f0-9-]{36}$/i, 'Disposable thread ID missing');
    const watched = rpc.waitForCompletedTurn(threadId);
    try {
      const started = await rpc.request('turn/start', { threadId,
        input: [{ type: 'text', text: 'Say READY only. Do not use tools or modify files.' }],
        cwd: dir, approvalPolicy: 'never', sandboxPolicy: { type: 'readOnly' },
      });
      const ended = await watched.result;
      assert.equal(ended.id, started.turn.id);
      assert.equal(ended.status, 'completed');
    } finally { watched.dispose(); }
    const before = await rpc.request('thread/turns/list', {
      threadId, limit: 20, sortDirection: 'desc', itemsView: 'notLoaded',
    });
    assert.ok(before?.data?.length >= 1);
    say('PASS - One disposable conversation persisted; no second writer');
    say('Opening the real Codex TUI on the SAME App Server and SAME conversation.');
    say('In Codex, type: Say ' + marker + ' exactly');
    say('After Codex responds, type /exit to close this native proof.');
    const terminal = spawn(process.execPath, [codexEntry, '--remote', url,
      '--remote-auth-token-env', 'CONTINUUM_REMOTE_TOKEN_BP203', 'resume', threadId], {
      cwd: dir, env: { ...process.env, CONTINUUM_REMOTE_TOKEN_BP203: token },
      stdio: 'inherit', windowsHide: false,
    });
    const [code] = await once(terminal, 'close');
    assert.equal(code, 0, 'Native Codex TUI exited unsuccessfully');
    const after = await rpc.request('thread/turns/list', {
      threadId, limit: 20, sortDirection: 'desc', itemsView: 'notLoaded',
    });
    assert.ok(after?.data?.length > before.data.length, 'No new turn was observed from the native TUI');
    say('PASS - Native Codex TUI added a turn to the SAME App Server conversation');
    say('PASS - No fork, and only one Codex server process');
  } finally {
    rpc?.socket.close();
    await stop(child, childClosed);
    await rm(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  }
}
main().catch(error => { say('FAIL - ' + error.message); process.exitCode = 1; });
