import { readFile } from 'node:fs/promises';
import { dirname, basename, isAbsolute } from 'node:path';
import { spawn } from 'node:child_process';
import { nativeTuiArguments, REMOTE_TOKEN_ENV } from './remote.mjs';
import { SharedSessionHost, locationFor } from './host.mjs';
import { connectToSession, terminalWatch } from './client.mjs';

const [mode, jobPath, codexEntry] = process.argv.slice(2);
if (
  !['host', 'watch', 'status', 'answer', 'native'].includes(mode) ||
  !isAbsolute(jobPath) ||
  (['host', 'native'].includes(mode) && !isAbsolute(codexEntry ?? ''))
) {
  console.error(
    'Usage: node main.mjs <host|watch|status|answer|native> ABSOLUTE_JOB_JSON [ABSOLUTE_CODEX_CLI_JS]',
  );
  process.exit(2);
}
const jobName = basename(jobPath, '.json');
const appDir = dirname(jobPath);
const { descriptor } = locationFor(appDir, jobName);
async function nativeCredentials(descriptorPath) {
  let socket,
    requested = false,
    settled = false;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => fail(new Error('Timed out requesting native terminal credentials')),
      5000,
    );
    const fail = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket?.destroy();
      reject(error);
    };
    const handle = (message) => {
      try {
        if (message.action === 'snapshot' && !requested) {
          requested = true;
          socket.write(JSON.stringify({ action: 'native-attach' }) + '\n');
        } else if (message.action === 'native-credentials') {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve({ credentials: message, lease: socket });
        } else if (message.action === 'error' || message.action === 'disconnected') {
          fail(new Error(message.message));
        }
      } catch (error) {
        fail(error);
      }
    };
    connectToSession(descriptorPath, handle).then((connection) => {
      socket = connection;
      if (settled && !socket.destroyed) socket.destroy();
    }, fail);
  });
}

async function run() {
  if (mode === 'host') {
    const job = JSON.parse(await readFile(jobPath, 'utf8'));
    const host = new SharedSessionHost({ job, jobName, appDir, codexEntry, remote: true });
    const quit = () => {
      host.fatal(new Error('Session host terminated'));
    };
    process.once('SIGINT', quit);
    process.once('SIGTERM', quit);
    try {
      const outcome = await host.begin();
      if (outcome !== 'completed') {
        console.error('Codex turn ended: ' + outcome);
        process.exitCode = 1;
      } else {
        console.log(
          'Codex scheduled turn completed; keeping the shared owner while a native TUI is attached.',
        );
        await host.waitForNativeViewers();
      }
    } finally {
      await host.close();
    }
  } else if (mode === 'native') {
    const job = JSON.parse(await readFile(jobPath, 'utf8'));
    if (job.executionMode !== 'shared') throw new Error('Native viewer requires a shared session');
    // Clicking Open in Terminal explicitly requests the real Codex TUI.
    // No new App Server, turn/start, prompt, or fork is issued here.
    const { credentials, lease } = await nativeCredentials(descriptor);
    try {
      if (
        !/^[a-f0-9]{64}$/i.test(credentials.token ?? '') ||
        credentials.threadId !== job.sessionId ||
        credentials.cwd !== job.repo
      )
        throw new Error('Invalid shared owner credentials');
      const args = nativeTuiArguments(codexEntry, credentials.endpoint, credentials.threadId);
      const terminal = spawn(process.execPath, args, {
        cwd: credentials.cwd,
        stdio: 'inherit',
        windowsHide: false,
        env: { ...process.env, [REMOTE_TOKEN_ENV]: credentials.token },
      });
      const result = await new Promise((resolve, reject) => {
        terminal.once('error', reject);
        terminal.once('close', (code, signal) => resolve(code ?? (signal ? 1 : 0)));
      });
      if (result !== 0) throw new Error('Native Codex TUI exited with code ' + result);
    } finally {
      // The owner tracks this named-pipe lease, not the TUI's WebSocket
      // activity. The lease ends when the actual terminal process exits.
      lease.end();
    }
  } else if (mode === 'watch') {
    await terminalWatch(descriptor);
  } else if (mode === 'status') {
    let socket;
    socket = await connectToSession(descriptor, (msg) => {
      if (msg.action === 'snapshot') {
        process.stdout.write(JSON.stringify(msg) + '\n');
        socket.end();
      }
    });
  } else {
    // Approval bodies arrive on stdin, never command arguments or process lists.
    const line = await new Promise((resolve) => {
      let value = '';
      process.stdin.setEncoding('utf8');
      process.stdin.on('data', (d) => {
        value += d;
        if (value.includes('\n')) resolve(value.split('\n')[0]);
      });
      process.stdin.on('end', () => resolve(value));
    });
    const command = JSON.parse(line);
    let socket;
    socket = await connectToSession(descriptor, (msg) => {
      if (msg.action === 'snapshot') socket.write(JSON.stringify(command) + '\n');
      if (['ack', 'error'].includes(msg.action)) {
        console.log(JSON.stringify(msg));
        socket.end();
        if (msg.action === 'error') process.exitCode = 1;
      }
    });
  }
}
run().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
