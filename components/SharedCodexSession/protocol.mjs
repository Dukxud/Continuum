import { EventEmitter } from 'node:events';
import { createInterface } from 'node:readline';

export class AppServerProtocol extends EventEmitter {
  constructor(child, { timeoutMs = 20000 } = {}) {
    super();
    this.child = child;
    this.timeoutMs = timeoutMs;
    this.nextId = 1;
    this.pending = new Map();
    this.closed = false;
    this.reader = createInterface({ input: child.stdout, crlfDelay: Infinity });
    this.reader.on('line', line => this.onLine(line));
    this.reader.on('close', () => this.fail(new Error('Codex App Server stdout closed')));
    child.on('error', error => this.fail(error));
    child.on('exit', (code, signal) => this.fail(new Error('Codex App Server exited: ' + (code ?? signal))));
  }
  send(message) {
    if (this.closed || !this.child.stdin.writable) throw new Error('Codex App Server not writable');
    this.child.stdin.write(JSON.stringify(message) + '\n');
  }
  request(method, params, timeoutMs = this.timeoutMs) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error('Codex ' + method + ' timed out'));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      try { this.send({ id, method, params }); }
      catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }
  respond(id, result) {
    this.send({ id, result });
  }
  onLine(line) {
    let message;
    try { message = JSON.parse(line); }
    catch { this.emit('malformed'); return; }
    if (message && Object.hasOwn(message, 'id') && !message.method) {
      const callback = this.pending.get(message.id);
      if (!callback) return;
      this.pending.delete(message.id);
      clearTimeout(callback.timer);
      if (message.error) callback.reject(new Error('Codex error ' + message.error.code + ': ' + message.error.message));
      else callback.resolve(message.result);
      return;
    }
    if (typeof message?.method === 'string') this.emit('message', message);
  }
  fail(error) {
    if (this.closed) return;
    this.closed = true;
    for (const { reject, timer } of this.pending.values()) { clearTimeout(timer); reject(error); }
    this.pending.clear();
    this.emit('closed', error);
  }
}
export const isUuid = value => typeof value === 'string' && /^[a-f\d]{8}-(?:[a-f\d]{4}-){3}[a-f\d]{12}$/i.test(value);
export const isJobName = value => typeof value === 'string' && /^CodexResume-\d{8}-\d{4}-[a-f\d]{8}$/i.test(value);
export const isServerRequest = method => [
  'item/commandExecution/requestApproval',
  'item/fileChange/requestApproval',
  'item/tool/requestUserInput',
  'mcpServer/elicitation/request',
  'item/permissions/requestApproval',
].includes(method);

export function validateUserResponse(request, result) {
  if (!request || !isServerRequest(request.method)) throw new Error('Unknown or expired request');
  if (!result || typeof result !== 'object' || Array.isArray(result)) throw new Error('Malformed response');
  if (request.method === 'item/commandExecution/requestApproval' || request.method === 'item/fileChange/requestApproval') {
    if (!['accept', 'acceptForSession', 'decline', 'cancel'].includes(result.decision)) throw new Error('Unsupported approval decision');
    if (Object.keys(result).length !== 1) throw new Error('Unexpected approval attributes');
  } else if (request.method === 'item/tool/requestUserInput') {
    const questions = request.params?.questions;
    if (!Array.isArray(questions) || !result.answers || typeof result.answers !== 'object' || Array.isArray(result.answers)) throw new Error('Malformed question answers');
    const allowed = new Set(questions.map(q => q.id));
    for (const [id, answer] of Object.entries(result.answers)) {
      if (!allowed.has(id) || !Array.isArray(answer?.answers) || answer.answers.some(a => typeof a !== 'string' || a.length > 4096)) throw new Error('Invalid question answer');
    }
  } else if (request.method === 'mcpServer/elicitation/request') {
    if (!['accept', 'decline', 'cancel'].includes(result.action)) throw new Error('Invalid elicitation decision');
    if (result.action !== 'accept' && result.content != null) throw new Error('Decline must not send content');
  } else {
    throw new Error('Permission-profile requests require a dedicated picker');
  }
  return result;
}
