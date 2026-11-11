'use strict';
// The Codex resume picker uses thread/list; a thread/read or rollout
// preview is not authoritative for a renamed conversation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const { normalizeThreadRead, readThreadSummaries } = require('../src/backend/CodexUsage.js');
const A = '00000000-0000-0000-0000-000000000001';
const B = '00000000-0000-0000-0000-000000000002';
const C = '00000000-0000-0000-0000-000000000003';

test('individual read remains metadata-only and validates session identity', () => {
  assert.deepEqual(
    normalizeThreadRead(
      {
        thread: {
          id: A,
          cwd: 'C:\\Users\\Example',
          name: '  AIV  ',
          preview: 'Opening prompt',
        },
      },
      A,
    ),
    { ok: true, threadId: A, cwd: 'C:\\Users\\Example', name: 'AIV', preview: 'Opening prompt' },
  );
  assert.throws(() => normalizeThreadRead({ thread: { id: B } }, A), /unexpected thread/);
});

test('canonical picker list wins over stale thread/read and opening messages', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-list-test-'));
  try {
    const stub = path.join(dir, 'codex.js');
    const script = String.raw`"use strict";
const readline=require('node:readline');
readline.createInterface({input:process.stdin}).on('line',line=>{
  let message;try{message=JSON.parse(line);}catch{return}
  const send=value=>process.stdout.write(JSON.stringify(value)+'\n');
  if(message.method==='initialize')return send({id:message.id,result:{}});
  if(message.method==='thread/read')return send({id:message.id,result:{
    thread:{id:message.params.threadId,name:null,preview:'# AIVault — Independent Adversarial Architecture Review'}
  }});
  if(message.method==='thread/list'){
    if(message.params.limit!==100 ||
       JSON.stringify(message.params.sourceKinds)!=='["cli","exec"]' ||
       message.params.archived!==false)
      return send({id:message.id,error:{message:'Incorrect picker source filters'}});
    const page=message.params.cursor==='next';
    const data=page?[{id:'00000000-0000-0000-0000-000000000003',
      name:'Restore frontend quality gate',preview:'Old title',cwd:'C:\\QA'}]:
      [{id:'00000000-0000-0000-0000-000000000001',name:'AIV',
        preview:'# AIVault — Independent Adversarial Architecture Review',cwd:'C:\\Users\\Example'},
       {id:'00000000-0000-0000-0000-000000000004',name:'Unrequested IDE thread'}];
    send({id:message.id,result:{data,nextCursor:page?null:'next'}});
  }
});
`;
    fs.writeFileSync(stub, script);
    const result = await readThreadSummaries(stub, [A, B, C], 4000);
    assert.equal(result.ok, true);
    assert.equal(result.threads[A].name, 'AIV');
    assert.match(result.threads[A].preview, /AIVault/);
    assert.equal(result.threads[B], undefined);
    assert.equal(result.threads[C].name, 'Restore frontend quality gate');
    assert.equal(Object.keys(result.threads).length, 2);
    await assert.rejects(() => readThreadSummaries(stub, ['invalid']), /Invalid thread/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
