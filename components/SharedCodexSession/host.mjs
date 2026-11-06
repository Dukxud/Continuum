import { createServer } from 'node:net';
import { spawn } from 'node:child_process';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, join } from 'node:path';
import { EventEmitter } from 'node:events';
import { AppServerProtocol, isJobName, isUuid, isServerRequest, validateUserResponse } from './protocol.mjs';

const MAX_INPUT_BYTES = 64 * 1024;
const MAX_EVENTS = 160;
const MAX_TEXT = 12000;

export function locationFor(appDir, jobName) {
  if (!isAbsolute(appDir) || !isJobName(jobName)) throw new Error('Invalid shared-session location');
  return {
    endpoint: process.platform === 'win32' ? '\\\\.\\pipe\\Continuum-' + jobName : join(appDir, jobName + '.sock'),
    descriptor: join(appDir, jobName + '.shared.json'),
  };
}
const limitText = value => String(value ?? '').slice(0, MAX_TEXT);

function publicEvent(message) {
  const { method, params = {} } = message;
  if (method === 'item/agentMessage/delta' || method === 'item/plan/delta') return { kind: 'text', method, text: limitText(params.delta) };
  if (method === 'item/started' || method === 'item/completed') {
    const item = params.item ?? {};
    return { kind: 'item', method, itemType: item.type, status: item.status ?? '', command: item.type === 'commandExecution' ? limitText(item.command) : undefined };
  }
  if (method === 'turn/started' || method === 'turn/completed') return { kind: 'turn', method, status: params.turn?.status ?? '' };
  if (method === 'error') return { kind: 'error', method, message: limitText(params.error?.message ?? params.message) };
  return null;
}

export class SharedSessionHost extends EventEmitter {
  constructor({ job, jobName, appDir, codexEntry, nodeBinary = process.execPath, spawnServer, shutdownGraceMs = 1000 }) {
    super();
    if (!isJobName(jobName) || !isUuid(job.sessionId) || !isAbsolute(job.repo) || !job.message?.trim()) throw new Error('Invalid scheduled session');
    if (!isAbsolute(codexEntry)) throw new Error('Codex JavaScript entry must be absolute');
    this.job = job;
    this.jobName = jobName;
    this.appDir = appDir;
    this.codexEntry = codexEntry;
    this.nodeBinary = nodeBinary;
    this.spawnServer = spawnServer ?? (() => spawn(nodeBinary, [codexEntry, 'app-server'], { stdio: ['pipe', 'pipe', 'pipe'], cwd: job.repo, windowsHide: true }));
    this.shutdownGraceMs = shutdownGraceMs;
    this.locations = locationFor(appDir, jobName);
    this.secret = randomBytes(32).toString('hex');
    this.sockets = new Set();
    this.pending = new Map();
    this.reviewableFileChanges = new Map();
    this.events = [];
    this.status = 'starting';
    this.turnId = null;
    this.completed = false;
    this.protocol = null;
    this.done = new Promise((resolve, reject) => { this.resolveDone = resolve; this.rejectDone = reject; });
    this.done.catch(() => {});
  }
  snapshot() {
    return { action: 'snapshot', status: this.status, job: this.jobName,
      pending: [...this.pending.values()].map(({ id, method, params }) => ({ id, method, params })),
      events: this.events, turnId: this.turnId };
  }
  broadcast(message) {
    const encoded = JSON.stringify(message) + '\n';
    for (const socket of this.sockets) {
      if (!socket.write(encoded)) { socket.destroy(); this.sockets.delete(socket); }
    }
  }
  event(message) {
    const event = publicEvent(message);
    if (!event) return;
    this.events.push(event);
    if (this.events.length > MAX_EVENTS) this.events.shift();
    this.broadcast({ action: 'event', event });
  }
  async begin() {
    await mkdir(this.appDir, { recursive: true });
    const { endpoint, descriptor } = this.locations;
    if (process.platform !== 'win32') await rm(endpoint, { force: true });
    this.server = createServer(socket => this.acceptSocket(socket));
    this.server.on('error', error => this.fatal(error));
    await new Promise((resolve, reject) => {
      this.server.once('error', reject);
      this.server.listen(endpoint, () => { this.server.off('error', reject); resolve(); });
    });
    const temp = descriptor + '.new';
    await writeFile(temp, JSON.stringify({ version: 1, job: this.jobName, endpoint, secret: this.secret, pid: process.pid }), { flag: 'wx', mode: 0o600 });
    await rename(temp, descriptor);
    try {
      const child = this.spawnServer();
      this.child = child;
      // The real Codex App Server can log extensively on stderr. Drain it,
      // without copying private process output into the shared UI snapshot,
      // so the pipe never blocks the single conversation owner.
      child.stderr?.resume();
      this.protocol = new AppServerProtocol(child);
      this.protocol.on('malformed', () => this.fatal(
        new Error('Codex App Server returned an invalid JSON-RPC message')));

      this.protocol.on('message', message => this.onAppMessage(message));
      this.protocol.on('closed', error => { if (!this.completed) this.fatal(error); });
      const initialized = await this.protocol.request('initialize', {
        clientInfo: { name: 'continuum_scheduler', title: 'Continuum Scheduler', version: '0.3.0' },
        capabilities: { experimentalApi: true },
      });
      if (!initialized) throw new Error('Codex initialization refused');
      this.protocol.send({ method: 'initialized', params: {} });
      const resumed = await this.protocol.request('thread/resume', { threadId: this.job.sessionId, excludeTurns: true });
      if (resumed?.thread?.id !== this.job.sessionId) throw new Error('Codex resumed a different conversation');
      const params = {
        threadId: this.job.sessionId,
        input: [{ type: 'text', text: this.job.message }],
        cwd: this.job.repo,
        approvalPolicy: this.job.access === 'yolo' ? 'never' : 'on-request',
        sandboxPolicy: this.job.access === 'yolo' ? { type: 'dangerFullAccess' }
          : this.job.access === 'read-only' ? { type: 'readOnly' }
          : { type: 'workspaceWrite', writableRoots: [this.job.repo], networkAccess: false },
      };
      if (this.job.model) params.model = this.job.model;
      if (this.job.effort) params.effort = this.job.effort;
      const started = await this.protocol.request('turn/start', params);
      if (!started?.turn?.id) throw new Error('Codex failed to acknowledge the turn');
      this.turnId = started.turn.id;
      if (!this.completed) this.status = 'running';
      this.broadcast(this.snapshot());
      return this.done;
    } catch (error) {
      this.fatal(error);
      throw error;
    }
  }
  onAppMessage(message) {
    if (this.completed) return;
    if (message.method === 'item/started' && message.params?.item?.type === 'fileChange') {
      const item = message.params.item;
      if (item.id && Array.isArray(item.changes)) {
        this.reviewableFileChanges.set(item.id,
          item.changes.slice(0, 16).map(change => ({
            path: limitText(change.path),
            kind: limitText(change.kind),
            diff: limitText(change.diff).slice(0, 2500),
          })));
      }
    }
    if (Object.hasOwn(message, 'id') && isServerRequest(message.method)) {
      if (message.params?.threadId !== this.job.sessionId) {
        this.fatal(new Error('Cross-thread Codex server request refused'));
        return;
      }
      const id = String(message.id);
      const params = { ...message.params };
      if (message.method === 'item/fileChange/requestApproval') {
        params.proposedChanges = this.reviewableFileChanges.get(params.itemId) ?? [];
      }
      this.pending.set(id, { id, method: message.method, params });
      this.status = 'needs-input';
      this.broadcast(this.snapshot());
      return;
    }
    if (Object.hasOwn(message, 'id') && message.method) {
      this.fatal(new Error('Unsupported Codex server request: ' + message.method));
      return;
    }
    if (message.method === 'serverRequest/resolved') {
      this.pending.delete(String(message.params?.requestId));
      if (!this.pending.size) this.status = 'running';
      this.broadcast(this.snapshot());
    }
    if (message.method === 'turn/completed') {
      if (message.params?.threadId !== this.job.sessionId ||
          (this.turnId && message.params?.turn?.id !== this.turnId)) {
        this.fatal(new Error('Unexpected thread or turn completion from Codex'));
        return;
      }
      const outcome = message.params?.turn?.status;
      this.status = outcome === 'completed' ? 'completed' : outcome === 'interrupted' ? 'interrupted' : 'failed';
      this.completed = true;
      this.pending.clear();
      this.event(message);
      this.broadcast(this.snapshot());
      this.resolveDone(this.status);
      return;
    }
    this.event(message);
  }
  acceptSocket(socket) {
    socket.setEncoding('utf8');
    let authenticated = false, input = '';
    socket.on('data', chunk => {
      input += chunk;
      if (Buffer.byteLength(input, 'utf8') > MAX_INPUT_BYTES) { socket.destroy(); return; }
      for (;;) {
        const breakAt = input.indexOf('\n');
        if (breakAt < 0) break;
        const current = input.slice(0, breakAt);
        input = input.slice(breakAt + 1);
        let command;
        try { command = JSON.parse(current); } catch { socket.destroy(); return; }
        if (!authenticated) {
          const supplied = Buffer.from(String(command.secret ?? ''), 'utf8');
          const expected = Buffer.from(this.secret);
          if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) { socket.destroy(); return; }
          authenticated = true;
          this.sockets.add(socket);
          socket.write(JSON.stringify(this.snapshot()) + '\n');
          continue;
        }
        this.command(command, socket);
      }
    });
    socket.on('close', () => this.sockets.delete(socket));
    socket.on('error', () => this.sockets.delete(socket));
  }
  async command(command, socket) {
    try {
      if (command.action === 'answer') {
        const id = String(command.id);
        const request = this.pending.get(id);
        validateUserResponse(request, command.result);
        this.pending.delete(id);
        this.protocol.respond(Number.isSafeInteger(Number(id)) ? Number(id) : id, command.result);
        if (!this.pending.size) this.status = 'running';
        this.broadcast(this.snapshot());
      } else if (command.action === 'steer') {
        if (this.completed || !this.turnId || typeof command.text !== 'string' || !command.text.trim() || command.text.length > 4000) throw new Error('Cannot steer this turn');
        await this.protocol.request('turn/steer', { threadId: this.job.sessionId, expectedTurnId: this.turnId,
          input: [{ type: 'text', text: command.text }] });
      } else if (command.action === 'status') {
        socket.write(JSON.stringify(this.snapshot()) + '\n');
      } else throw new Error('Unknown action');
      socket.write(JSON.stringify({ action: 'ack', requestAction: command.action, id: command.id ?? null }) + '\n');
    } catch (error) {
      socket.write(JSON.stringify({ action: 'error', message: error.message.slice(0, 200) }) + '\n');
    }
  }
  fatal(error) {
    if (this.completed) return;
    this.status = 'failed';
    this.completed = true;
    this.pending.clear();
    this.broadcast({ action: 'fatal', message: limitText(error.message) });
    this.rejectDone(error);
  }
  async close() {
    for (const socket of this.sockets) socket.end();
    await new Promise(resolve => this.server?.close(() => resolve()) ?? resolve());
    if (this.child && this.child.exitCode === null) {
      this.child.kill();
      await Promise.race([new Promise(resolve => this.child.once('exit', resolve)),
        new Promise(resolve => setTimeout(resolve, this.shutdownGraceMs))]);
      if (this.child.exitCode === null) this.child.kill('SIGKILL');
    }
    await rm(this.locations.descriptor, { force: true });
    if (process.platform !== 'win32') await rm(this.locations.endpoint, { force: true });
  }
}

export async function loadDescriptor(path) {
  const descriptor = JSON.parse(await readFile(path, 'utf8'));
  if (descriptor.version !== 1 || !isJobName(descriptor.job) || !descriptor.secret ||
      typeof descriptor.endpoint !== 'string') throw new Error('Invalid owner descriptor');
  return descriptor;
}
