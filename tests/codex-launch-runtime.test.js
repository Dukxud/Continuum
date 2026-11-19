'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const helper = path.resolve(__dirname, '../src/backend/CodexUsage.js');
const id = '0199aaaa-1234-4567-89ab-0000e116d411';

function fixture() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'continuum codex launch '));
}

function stopFixtureProcesses(directory) {
  for (const name of ['native.pid', 'wrapper.pid']) {
    try {
      const pid = Number(fs.readFileSync(path.join(directory, name), 'utf8'));
      if (Number.isInteger(pid) && pid > 1) process.kill(pid, 'SIGKILL');
    } catch {}
  }
}

function runHelper(directory, flags, timeoutMs = 4000) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [helper, ...flags], {
      cwd: directory,
      env: { ...process.env, CODEX_HOME: directory },
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    let stdout = '',
      stderr = '';
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      stopFixtureProcesses(directory);
      reject(
        new Error(
          stdout.includes('"ok":true')
            ? 'Helper returned JSON but did not exit: a descendant retained inherited pipes.'
            : `Helper did not finish: ${stdout} ${stderr}`,
        ),
      );
    }, timeoutMs);
    child.stdout.on('data', (chunk) => (stdout += chunk));
    child.stderr.on('data', (chunk) => (stderr += chunk));
    child.once('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.once('close', (code) => {
      clearTimeout(timer);
      const lines = stdout.trim().split(/\r?\n/);
      try {
        assert.equal(lines.length, 1, `Expected one JSON reply, got: ${stdout}`);
        resolve({ code, reply: JSON.parse(lines[0]), stderr });
      } catch (error) {
        reject(error);
      }
    });
  });
}

const server = `
const fs = require('node:fs');
const readline = require('node:readline');
const id = ${JSON.stringify(id)};
const thread = {id, cwd: process.cwd(), source: 'cli', preview: 'Horizon', name: 'Horizon', updatedAt: 1795040000};
const send = value => process.stdout.write(JSON.stringify(value) + '\\n');
let initialized = false;
readline.createInterface({input: process.stdin}).on('line', line => {
 const message = JSON.parse(line);
 if (message.method === 'initialize') return send({id: message.id, result: {}});
 if (message.method === 'initialized') {initialized = true; return;}
 if (!initialized) throw new Error('Handshake missing');
 if (message.method === 'thread/read') {
  if (message.params.includeTurns !== false) throw new Error('Unexpected history request');
  return send({id: message.id, result: {thread}});
 }
 if (message.method === 'thread/list') return send({id: message.id, result: {data: [thread], nextCursor: null}});
 throw new Error('Unexpected request: ' + message.method);
});
`;

test('native Codex entries support all metadata paths without a command shell', async () => {
  const directory = fixture();
  try {
    // The real Node executable acts as a native command. Its app-server script
    // verifies the exact argv that a standalone Codex executable receives.
    fs.writeFileSync(
      path.join(directory, 'app-server'),
      `if (JSON.stringify(process.argv.slice(2)) !== '["--listen","stdio://"]') throw new Error('Incorrect native argv');\n${server}`,
    );
    for (const query of [['--thread-id', id], ['--thread-ids', id], ['--sessions']]) {
      const result = await runHelper(directory, ['--cli-exe', process.execPath, ...query]);
      assert.equal(result.code, 0, JSON.stringify(result));
      assert.equal(result.reply.ok, true);
      const thread = result.reply.sessions?.[0] || result.reply.threads?.[id] || result.reply;
      assert.equal(thread.threadId, id);
      assert.equal(thread.cwd, directory);
    }
  } finally {
    stopFixtureProcesses(directory);
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('npm wrapper shutdown cannot leave a native descendant holding inherited pipes', async () => {
  const directory = fixture();
  try {
    fs.writeFileSync(
      path.join(directory, 'native-server.js'),
      `${server}\n` +
        `const timer = setInterval(() => fs.writeFileSync('heartbeat', String(Date.now())), 25);\n` +
        // Keep the native process alive after EOF and ignore Unix SIGTERM.
        // Forced tree termination must also handle a stalled server shutdown.
        `process.on('SIGTERM', () => {});\n` +
        `setTimeout(() => process.exit(0), 15000).unref();\n`,
    );
    const wrapper = path.join(directory, 'codex.js');
    fs.writeFileSync(
      wrapper,
      `const fs = require('node:fs');
const {spawn} = require('node:child_process');
fs.writeFileSync('wrapper.pid', String(process.pid));
const native = spawn(process.execPath, ['native-server.js'], {stdio: 'inherit'});
fs.writeFileSync('native.pid', String(native.pid));
native.on('exit', code => process.exit(code || 0));
// Emulate Windows TerminateProcess: the wrapper disappears without forwarding
// a signal to the native process that inherited the protocol pipes.
process.on('SIGTERM', () => process.exit(143));
`,
    );
    const result = await runHelper(directory, ['--cli-js', wrapper, '--thread-id', id], 4000);
    assert.equal(result.code, 0, JSON.stringify(result));
    assert.equal(result.reply.threadId, id);
    const heartbeat = fs.readFileSync(path.join(directory, 'heartbeat'), 'utf8');
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.equal(fs.readFileSync(path.join(directory, 'heartbeat'), 'utf8'), heartbeat);
  } finally {
    stopFixtureProcesses(directory);
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native launch rejects shell shims instead of executing through a shell', async () => {
  const directory = fixture();
  try {
    for (const name of ['codex.cmd', 'codex.bat', 'codex.ps1']) {
      const shim = path.join(directory, name);
      fs.writeFileSync(shim, 'echo must-not-execute');
      const result = await runHelper(directory, ['--cli-exe', shim, '--thread-id', id]);
      assert.equal(result.code, 1);
      assert.equal(result.reply.ok, false);
      assert.match(result.reply.error, /native.*executable/i);
    }
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
