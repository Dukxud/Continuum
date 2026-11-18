'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const {
  normalizeThreadRead,
  readThreadSummaries,
  readRecentCliThreads,
} = require('../src/backend/CodexUsage.js');

const A = '00000000-0000-0000-0000-000000000001';
const B = '00000000-0000-0000-0000-000000000002';

async function withServer(handler, run) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-discovery-'));
  const script = path.join(dir, 'codex.js');
  const log = path.join(dir, 'requests.jsonl');
  fs.writeFileSync(
    script,
    `'use strict';
const fs = require('node:fs');
const readline = require('node:readline');
const send = value => process.stdout.write(JSON.stringify(value) + '\\n');
let ready = false;
readline.createInterface({input:process.stdin}).on('line', line => {
  const message = JSON.parse(line);
  fs.appendFileSync(${JSON.stringify(log)}, line + '\\n');
  if (message.method === 'initialize') return send({id:message.id,result:{}});
  if (message.method === 'initialized') { ready = true; return; }
  if (!ready) return send({id:message.id,error:{message:'handshake missing'}});
  ${handler}
});
`,
  );
  try {
    await run(script, () => fs.readFileSync(log, 'utf8').trim().split('\n').map(JSON.parse));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('thread metadata preserves discovery provenance without inventing missing fields', () => {
  const metadata = normalizeThreadRead(
    {
      thread: {
        id: A,
        cwd: 'C:\\Users\\Example',
        name: 'Horizon',
        preview: '# Horizon',
        path: 'C:\\Users\\Example\\.codex\\sessions\\rollout.jsonl.zst',
        source: 'cli',
        updatedAt: 1795040000,
        gitInfo: {
          originUrl: 'https://github.com/example/Horizon.git',
          branch: 'main',
          sha: 'abc',
        },
      },
    },
    A,
  );
  assert.equal(metadata.source, 'cli');
  assert.match(metadata.path, /[.]jsonl[.]zst$/);
  assert.equal(metadata.updatedAt, 1795040000);
  assert.equal(metadata.gitInfo.originUrl, 'https://github.com/example/Horizon.git');
  assert.equal(normalizeThreadRead({ thread: { id: A } }, A).source, null);
  assert.equal(normalizeThreadRead({ thread: { id: A } }, A).path, null);
});

test('old active selected thread is recovered by exact ID beyond the bounded list', async () => {
  await withServer(
    `if (message.method === 'thread/list') {
      const page = Number(message.params.cursor || 0);
      return send({id:message.id,result:{data:[],nextCursor:String(page + 1)}});
    }
    if (message.method === 'thread/read') {
      if (message.params.includeTurns !== false) return send({id:message.id,error:{message:'history requested'}});
      return send({id:message.id,result:{thread:{id:message.params.threadId,source:'cli',preview:'# Horizon',cwd:'C:\\\\Users\\\\Example'}}});
    }`,
    async (script, requests) => {
      const result = await readThreadSummaries(script, [A], 4000);
      assert.equal(result.threads[A]?.preview, '# Horizon');
      assert.equal(result.partial, false);
      const calls = requests();
      assert.equal(calls.filter((m) => m.method === 'thread/list').length, 6);
      assert.equal(calls.filter((m) => m.method === 'thread/read').length, 1);
      assert.ok(
        calls
          .filter((m) => m.method === 'thread/list')
          .every((m) => m.params.sortKey === 'updated_at'),
      );
    },
  );
});

test('exact-ID fallback preserves picker names and rejects a mismatched thread response', async () => {
  await withServer(
    `if (message.method === 'thread/list') return send({id:message.id,result:{data:[{id:${JSON.stringify(A)},name:'Current picker name',source:'cli'}],nextCursor:null}});
    if (message.method === 'thread/read') return send({id:message.id,result:{thread:{id:${JSON.stringify(A)},name:'Unrelated read',source:'cli'}}});`,
    async (script, requests) => {
      const result = await readThreadSummaries(script, [A, B], 4000);
      assert.equal(result.threads[A].name, 'Current picker name');
      assert.equal(result.threads[B], undefined);
      assert.equal(result.partial, true);
      assert.deepEqual(
        requests()
          .filter((m) => m.method === 'thread/read')
          .map((m) => m.params.threadId),
        [B],
      );
    },
  );
});

test('unresponsive listing falls back and unresolved reads stop at the overall deadline', async () => {
  await withServer(
    `if (message.method === 'thread/read' && message.params.threadId === ${JSON.stringify(A)}) return send({id:message.id,result:{thread:{id:message.params.threadId,source:'cli',preview:'# Horizon'}}});`,
    async (script, requests) => {
      const started = Date.now();
      const result = await readThreadSummaries(script, [A, B], 1200);
      assert.equal(result.threads[A]?.preview, '# Horizon');
      assert.equal(result.threads[B], undefined);
      assert.equal(result.partial, true);
      assert.ok(Date.now() - started < 3000);
      assert.equal(requests().filter((m) => m.method === 'thread/read').length, 2);
    },
  );
});

test('recent session inventory accepts compressed CLI/exec metadata and rejects unsupported sources', async () => {
  await withServer(
    `if (message.method === 'thread/list') {
      if (message.params.limit !== 30 || message.params.sortKey !== 'updated_at' || message.params.archived !== false || JSON.stringify(message.params.sourceKinds) !== '["cli","exec"]') return send({id:message.id,error:{message:'incorrect inventory filters'}});
      return send({id:message.id,result:{data:[
        {id:${JSON.stringify(A)},source:'cli',path:'C:\\\\rollout.jsonl.zst',cwd:'C:\\\\Projects\\\\Horizon',preview:'# Horizon',updatedAt:200},
        {id:${JSON.stringify(B)},source:'exec',path:null,cwd:'C:\\\\Projects\\\\Other',updatedAt:100},
        {id:'00000000-0000-0000-0000-000000000003',source:'vscode',cwd:'C:\\\\Wrong'},
        {id:'bad',source:'cli'},
        {id:${JSON.stringify(A)},source:'cli',preview:'duplicate'}
      ],nextCursor:null}});
    }`,
    async (script, requests) => {
      const result = await readRecentCliThreads(script, 4000);
      assert.deepEqual(
        result.sessions.map((session) => session.threadId),
        [A, B],
      );
      assert.match(result.sessions[0].path, /[.]jsonl[.]zst$/);
      assert.equal(result.sessions[1].path, null);
      assert.equal(result.partial, false);
      assert.equal(requests().filter((m) => m.method === 'thread/read').length, 0);
    },
  );
});
