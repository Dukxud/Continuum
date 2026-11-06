import { createServer } from 'node:net';
import { once } from 'node:events';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { AppServerProtocol } from './protocol.mjs';

const CONNECT_ATTEMPTS = 30;
const RETRY_DELAY_MS = 150;
const MAX_MESSAGE_BYTES = 1024 * 1024;
export const REMOTE_TOKEN_ENV = 'CONTINUUM_CODEX_REMOTE_TOKEN';

export async function unusedLoopbackPort() {
  const server = createServer();
  try {
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    return server.address().port;
  } finally {
    if (server.listening) {
      await new Promise(resolve => server.close(resolve));
    }
  }
}

export function nativeTuiArguments(codexEntry, endpoint, threadId) {
  if (!/^[a-f\d]{8}-(?:[a-f\d]{4}-){3}[a-f\d]{12}$/i.test(threadId) ||
      !/^ws:\/\/127\.0\.0\.1:\d{1,5}$/.test(endpoint)) {
    throw new Error('Native TUI requires a loopback owner and a saved thread');
  }
  return [codexEntry, '--remote', endpoint,
    '--remote-auth-token-env', REMOTE_TOKEN_ENV, 'resume', threadId];
}

async function dial(endpoint, token, makeSocket, timeoutMs) {
  const socket = makeSocket(endpoint, { headers: { Authorization: 'Bearer ' + token } });
  try {
    await new Promise((resolve, reject) => {
      let settled = false;
      const done = error => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        socket.removeEventListener('open', onOpen);
        socket.removeEventListener('error', onError);
        socket.removeEventListener('close', onClose);
        if (error) reject(error); else resolve();
      };
      const onOpen = () => done();
      const onError = () => done(new Error('Codex WebSocket authentication or connection failed'));
      const onClose = () => done(new Error('Codex WebSocket closed during connection'));
      const timer = setTimeout(() => done(new Error('Codex WebSocket connection timed out')), timeoutMs);
      socket.addEventListener('open', onOpen);
      socket.addEventListener('error', onError);
      socket.addEventListener('close', onClose);
    });
    return socket;
  } catch (error) {
    // Closing a socket that never completed its handshake can itself throw.
    try { socket.close(); } catch { /* The connection was never usable. */ }
    throw error;
  }
}

/**
 * Adapts a WebSocket text-frame channel to the existing, tested JSON-RPC
 * protocol. This is one CLIENT connection, not another Codex App Server.
 * The Codex process is spawned exactly once by SharedSessionHost.
 */
export async function openRemoteProtocol({
  endpoint, token, child, makeSocket = (url, options) => new WebSocket(url, options),
  attempts = CONNECT_ATTEMPTS, retryMs = RETRY_DELAY_MS,
}) {
  if (!/^ws:\/\/127\.0\.0\.1:\d{1,5}$/.test(endpoint) ||
      !/^[a-f0-9]{64}$/i.test(token)) {
    throw new Error('Remote Codex connection must use authenticated loopback');
  }
  let socket, lastError;
  for (let attempt = 0; attempt < attempts; attempt++) {
    if (child.exitCode !== null || child.signalCode !== null) {
      throw new Error('Codex App Server exited before accepting connections');
    }
    try {
      socket = await dial(endpoint, token, makeSocket, 750);
      break;
    } catch (error) {
      lastError = error;
      if (attempt + 1 < attempts) await new Promise(resolve => setTimeout(resolve, retryMs));
    }
  }
  if (!socket) throw lastError ?? new Error('Codex App Server listener unavailable');

  const messages = new PassThrough();
  const channel = new EventEmitter();
  channel.stdout = messages;
  channel.stdin = {
    get writable() { return socket.readyState === 1; },
    write(value) {
      if (socket.readyState !== 1) throw new Error('Codex WebSocket disconnected');
      socket.send(value.trimEnd());
      return true;
    },
  };
  const protocol = new AppServerProtocol(channel);
  let closed = false;
  const fail = error => {
    if (closed) return;
    closed = true;
    protocol.fail(error);
    messages.end();
  };
  socket.addEventListener('message', event => {
    const message = event.data;
    if (typeof message !== 'string' || Buffer.byteLength(message, 'utf8') > MAX_MESSAGE_BYTES) {
      fail(new Error('Codex WebSocket message invalid or oversized'));
      socket.close();
      return;
    }
    messages.write(message + '\n');
  });
  socket.addEventListener('error', () => fail(new Error('Codex WebSocket transport failed')));
  socket.addEventListener('close', () => fail(new Error('Codex WebSocket disconnected')));
  return {
    protocol,
    close() {
      fail(new Error('Codex WebSocket connection closed'));
      socket.close();
    },
  };
}
