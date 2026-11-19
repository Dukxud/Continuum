import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SharedSessionHost, codexProcessCommand } from '../components/SharedCodexSession/host.mjs';
import { nativeTuiArguments } from '../components/SharedCodexSession/remote.mjs';

const sessionId = '0199aaaa-1234-4567-89ab-0000e116d411';
const jobName = 'CodexResume-20261119-1220-abcd1234';

test('shared owner launches native and npm entries with the same App Server argv', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'continuum shared launch '));
  try {
    const script = 'process.stdout.write(JSON.stringify(process.argv.slice(2)));';
    await writeFile(join(directory, 'app-server'), script);
    const npmEntry = join(directory, 'codex.mjs');
    await writeFile(npmEntry, script);
    for (const native of [true, false]) {
      const host = new SharedSessionHost({
        job: { sessionId, repo: directory, message: 'Fixture only.' },
        jobName,
        appDir: directory,
        codexEntry: native ? process.execPath : npmEntry,
        // A native executable must not be handed to Node, even if the configured
        // Node path cannot execute. The test never starts a shared session.
        nodeBinary: native ? join(directory, 'unavailable-node') : process.execPath,
      });
      const child = host.spawnServer(['--listen', 'stdio://']);
      let output = '';
      child.stdout.on('data', (chunk) => (output += chunk));
      await new Promise((resolve, reject) => {
        child.once('error', reject);
        child.once('close', (code) => {
          if (code) reject(new Error('Fixture native process failed: ' + code));
          else resolve();
        });
      });
      assert.deepEqual(
        JSON.parse(output),
        native ? ['--listen', 'stdio://'] : ['app-server', '--listen', 'stdio://'],
      );
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('native TUI attaches through the selected executable without putting tokens in argv', () => {
  for (const entry of [process.execPath, join(tmpdir(), 'codex.js')]) {
    const args = nativeTuiArguments(entry, 'ws://127.0.0.1:43129', sessionId);
    const command = codexProcessCommand(entry, args.slice(1));
    assert.equal(command.executable, process.execPath);
    assert.deepEqual(command.args, entry.endsWith('.js') ? args : args.slice(1));
    assert.equal(command.args.includes('resume'), true);
    assert.equal(command.args.includes('--remote-auth-token-env'), true);
  }
  assert.throws(() => codexProcessCommand(join(tmpdir(), 'codex.cmd'), []), /shell shim/);
  assert.throws(() => codexProcessCommand('codex.exe', []), /absolute/);
});
