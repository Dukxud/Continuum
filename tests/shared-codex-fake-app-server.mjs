import { createInterface } from 'node:readline';
const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
const threadId = process.env.FAKE_THREAD_ID;
const turnId = 'turn-fake-1';
const send = value => process.stdout.write(JSON.stringify(value) + '\n');
rl.on('line', line => {
  const message = JSON.parse(line);
  const { method, id } = message;
  if (method === 'initialize') send({ id, result: { userAgent: 'fake' } });
  else if (method === 'thread/resume') send({ id, result: { thread: { id: threadId } } });
  else if (method === 'turn/start') {
    send({ id, result: { turn: { id: turnId, status: 'inProgress' } } });
    send({ method: 'turn/started', params: { threadId, turn: { id: turnId, status: 'inProgress' } } });
    send({ method: 'item/agentMessage/delta', params: { delta: 'Visible stream text', threadId } });
    send({ id: 100, method: 'item/commandExecution/requestApproval', params: {
      threadId, turnId, command: 'echo verify', reason: 'Needs permission',
    } });
  } else if (id === 100) {
    if (message.result?.decision !== 'accept') { process.exit(13); return; }
    send({ method: 'serverRequest/resolved', params: { threadId, requestId: 100 } });
    send({ id: 101, method: 'item/tool/requestUserInput', params: {
      threadId, turnId, questions: [{ id: 'choice', question: 'Proceed with work?', options: [{ label: 'Yes' }, { label: 'No' }] }],
    } });
  } else if (id === 101) {
    if (message.result?.answers?.choice?.answers?.[0] !== 'Yes') { process.exit(14); return; }
    send({ method: 'serverRequest/resolved', params: { threadId, requestId: 101 } });
    send({ method: 'turn/completed', params: { threadId, turn: { id: turnId, status: 'completed' } } });
  } else if (method === 'turn/steer') send({ id, result: { turnId } });
});
