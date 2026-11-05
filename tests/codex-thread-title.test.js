"use strict";
// Codex-owned title support, including read-only batching and partial failures.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {test} = require('node:test');
const {normalizeThreadRead, readThreadSummaries} = require('../CodexUsage.js');
const A='00000000-0000-0000-0000-000000000001';
const B='00000000-0000-0000-0000-000000000002';
const C='00000000-0000-0000-0000-000000000003';

test('official thread/read preserves the user-facing title',()=>{
  assert.deepEqual(normalizeThreadRead({thread:{
    id:A,cwd:'C:\\Users\\Example',name:'  Review shared-EC2 architecture  ',
    preview:'First generic user prompt'
  }},A),{
    ok:true,threadId:A,cwd:'C:\\Users\\Example',
    name:'Review shared-EC2 architecture',preview:'First generic user prompt'
  });
  assert.throws(()=>normalizeThreadRead({thread:{id:B}},A),/unexpected thread/);
});

test('one read-only app-server batches titles; failed threads do not hide the rest',async()=>{
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'codex-title-test-'));
  try{
    const stub=path.join(temp,'codex.js');
    const script=String.raw`"use strict";
const readline=require('node:readline');
readline.createInterface({input:process.stdin}).on('line',line=>{
  let message;try{message=JSON.parse(line)}catch{return}
  const send=value=>process.stdout.write(JSON.stringify(value)+'\n');
  if(message.method==='initialize')send({id:message.id,result:{}});
  if(message.method==='thread/read') {
    const id=message.params.threadId;
    if(message.params.includeTurns!==false) {
      send({id:message.id,error:{message:'includeTurns must be false'}});
    } else if(id==='00000000-0000-0000-0000-000000000002') {
      send({id:message.id,error:{message:'unavailable session'}});
    } else {
      send({id:message.id,result:{thread:{
        id, name:id.endsWith('1')?'Review shared-EC2 architecture':null,
        preview:'First user prompt',cwd:'C:\\Example'
      }}});
    }
  }
});
`;
    fs.writeFileSync(stub,script);
    const result=await readThreadSummaries(stub,[A,B,C],4000);
    assert.equal(result.ok,true);
    assert.equal(result.partial,undefined);
    assert.equal(result.threads[A].name,'Review shared-EC2 architecture');
    assert.equal(result.threads[A].preview,'First user prompt');
    assert.equal(result.threads[B],undefined);
    assert.equal(result.threads[C].name,null);
    await assert.rejects(()=>readThreadSummaries(stub,['not-a-uuid']),/Invalid thread/);
  }finally{fs.rmSync(temp,{recursive:true,force:true})}
});
