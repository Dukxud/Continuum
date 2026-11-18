'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { normalizeThreadRead, readThreadDirectory } = require('../src/backend/CodexUsage.js');
const id = '01234567-1234-4567-89ab-0123456789ab';
const mock = path.join(__dirname, 'mock-app-server.js');
const absentDiscoveryMetadata = { source: null, path: null, updatedAt: null, gitInfo: null };
test('read-only thread/read uses handshake and preserves the saved cwd', async () => {
  const result = await readThreadDirectory(mock, id, 5000);
  assert.deepEqual(result, {
    ok: true,
    threadId: id,
    cwd: 'C:\\Projects\\CodexSample',
    name: null,
    preview: null,
    ...absentDiscoveryMetadata,
  });
});
test('metadata must belong to the selected conversation', () => {
  assert.throws(
    () => normalizeThreadRead({ thread: { id: 'other', cwd: 'C:\\evil' } }, id),
    /unexpected thread/,
  );
  assert.throws(() => normalizeThreadRead({}, id), /unexpected thread/);
});
test('missing cwd is not guessed', () => {
  assert.deepEqual(normalizeThreadRead({ thread: { id, cwd: null } }, id), {
    ok: true,
    threadId: id,
    cwd: null,
    name: null,
    preview: null,
    ...absentDiscoveryMetadata,
  });
  assert.deepEqual(normalizeThreadRead({ thread: { id, cwd: '   ' } }, id), {
    ok: true,
    threadId: id,
    cwd: null,
    name: null,
    preview: null,
    ...absentDiscoveryMetadata,
  });
});
test('explicit non-CLI sources stay distinct from missing legacy metadata', () => {
  for (const [source, expected] of [
    ['cli', 'cli'],
    ['exec', 'exec'],
    ['vscode', 'vscode'],
    [{ custom: 'cli' }, 'custom'],
    [{ subAgent: 'review' }, 'subAgent'],
    [{ futureSource: 'cli' }, 'unknown'],
    [{}, 'unknown'],
    [['cli'], 'unknown'],
    [42, 'unknown'],
    [false, 'unknown'],
    ['', 'unknown'],
    ['   ', 'unknown'],
  ]) {
    assert.equal(
      normalizeThreadRead({ thread: { id, source } }, id).source,
      expected,
      `Explicit source ${JSON.stringify(source)} must not become legacy missing metadata`,
    );
  }
  assert.equal(normalizeThreadRead({ thread: { id } }, id).source, null);
  assert.equal(normalizeThreadRead({ thread: { id, source: null } }, id).source, null);
});
test('invalid ids are rejected before starting Codex', async () => {
  await assert.rejects(
    readThreadDirectory(mock, '../../unsafe', 5000),
    /Invalid Codex conversation ID/,
  );
});
