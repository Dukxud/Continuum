import { connect } from 'node:net';
import { createInterface } from 'node:readline';
import { loadDescriptor } from './host.mjs';

export async function connectToSession(descriptorPath, onMessage) {
  const { endpoint, secret } = await loadDescriptor(descriptorPath);
  return new Promise((resolve, reject) => {
    const socket = connect(endpoint);
    let input = '', authenticated = false, settled = false, snapshotDelivered = false;
    const buffered = [];
    const timer = setTimeout(() => {
      if (!authenticated) { reject(new Error('Shared owner authentication timed out')); socket.destroy(); }
    }, 5000);
    const fail = error => {
      clearTimeout(timer);
      if (!settled) { settled = true; reject(error); }
      else onMessage({ action: 'disconnected', message: error.message });
    };
    socket.once('error', fail);
    socket.on('close', () => {
      if (!settled) fail(new Error('Shared owner disconnected before authentication'));
    });
    socket.once('connect', () => socket.write(JSON.stringify({ secret }) + '\n'));
    socket.setEncoding('utf8');
    socket.on('data', chunk => {
      input += chunk;
      if (Buffer.byteLength(input, 'utf8') > 256 * 1024) {
        socket.destroy(new Error('Shared owner message exceeded size limit'));
        return;
      }
      for (;;) {
        const i = input.indexOf('\n');
        if (i < 0) return;
        const line = input.slice(0, i);
        input = input.slice(i + 1);
        let msg;
        try { msg = JSON.parse(line); }
        catch { socket.destroy(new Error('Invalid shared owner response')); return; }
        if (!authenticated) {
          if (msg.action !== 'snapshot') {
            socket.destroy(new Error('Shared owner did not authenticate'));
            return;
          }
          authenticated = true;
          settled = true;
          clearTimeout(timer);
          resolve(socket);
          // The caller must receive its socket before its first snapshot.
          queueMicrotask(() => {
            onMessage(msg);
            snapshotDelivered = true;
            for (const event of buffered) onMessage(event);
            buffered.length = 0;
          });
        } else if (!snapshotDelivered) {
          buffered.push(msg);
        } else {
          onMessage(msg);
        }
      }
    });
  });
}

function displayRequest(request, output) {
  const p = request.params ?? {};
  if ((request.method === 'item/tool/requestUserInput' || request.method === 'tool/requestUserInput')) {
    for (const question of p.questions ?? []) {
      output.write('\n? ' + (question.question ?? question.header ?? 'Codex question') + '\n');
      for (const [index, option] of (question.options ?? []).entries()) output.write('  ' + (index + 1) + '. ' + option.label + '\n');
    }
    output.write('Answer (choose number or type text): ');
    return;
  }
  if (request.method.endsWith('requestApproval')) {
    output.write('\nApproval requested: ' + (p.reason ?? '') + '\n');
    if (p.command) output.write(p.command + '\n');
    if (p.networkApprovalContext) {
      const net = p.networkApprovalContext;
      output.write('Network: ' + (net.protocol ?? '') + '://' + (net.host ?? '') + (net.port == null ? '' : ':' + net.port) + '\n');
    }
    if (p.grantRoot) output.write('Access root: ' + p.grantRoot + '\n');
    for (const change of p.proposedChanges ?? []) {
      output.write('Change ' + change.kind + ': ' + change.path + '\n' + change.diff + '\n');
    }
    const safe = request.method === 'item/fileChange/requestApproval'
      ? (p.proposedChanges?.length ?? 0) > 0 && p.previewComplete === true
      : !!(p.command || (p.networkApprovalContext?.host && p.networkApprovalContext?.protocol));
    if (!safe) output.write('Approval disabled: no reviewable command/change details.\n');
    output.write(safe ? '[a]pprove / [d]ecline / [c]ancel: ' : '[d]ecline / [c]ancel: ');
    return;
  }
  output.write('\nCodex needs input (' + request.method + '); use Continuum to respond.\n');
}

export async function terminalWatch(descriptorPath, input = process.stdin, output = process.stdout) {
  const rl = createInterface({ input, output, terminal: !!output.isTTY });
  let socket, pending = [], answering = false, questionIndex = 0, answers = {}, replayed = false;
  let lastStatus = '';
  function promptNext() {
    if (answering || !pending.length) return;
    answering = true; questionIndex = 0; answers = {};
    displayRequest(pending[0], output);
  }
  socket = await connectToSession(descriptorPath, msg => {
    if (msg.action === 'snapshot') {
      if (lastStatus !== msg.status) { output.write('\n[Codex: ' + msg.status + ']\n'); lastStatus = msg.status; }
      if (!replayed) {
        replayed = true;
        for (const event of msg.events ?? []) if (event.kind === 'text') output.write(event.text);
      }
      const pendingIds = new Set((msg.pending ?? []).map(r => r.id));
      pending = pending.filter(r => pendingIds.has(r.id));
      for (const request of msg.pending ?? []) if (!pending.some(p => p.id === request.id)) pending.push(request);
      if (!pending.length) answering = false;
      promptNext();
      if (['completed','failed','interrupted'].includes(msg.status)) {
        output.write('\n[Turn ended]\n'); rl.close(); socket?.end();
      }
    } else if (msg.action === 'event') {
      const event = msg.event;
      if (event.kind === 'text') output.write(event.text);
      else if (event.kind === 'item' && event.itemType === 'commandExecution' && event.method === 'item/started') {
        output.write('\n$ ' + (event.command ?? '') + '\n');
      }
    } else if (msg.action === 'fatal' || msg.action === 'error') {
      output.write('\n[' + msg.action + '] ' + msg.message + '\n');
      if (msg.action === 'error') socket?.write(JSON.stringify({ action: 'status' }) + '\n');
    }
  });
  rl.on('line', line => {
    if (pending.length) {
      const request = pending[0];
      let result;
      if ((request.method === 'item/tool/requestUserInput' || request.method === 'tool/requestUserInput')) {
        const question = request.params.questions[questionIndex];
        const choice = Number(line.trim());
        const selected = Number.isInteger(choice) && choice >= 1 ? question.options?.[choice-1]?.label : undefined;
        answers[question.id] = { answers: [selected ?? ('user_note: ' + line.trim())] };
        if (++questionIndex < request.params.questions.length) {
          const next = request.params.questions[questionIndex];
          output.write('\n? ' + next.question + '\n');
          for (const [idx, option] of (next.options ?? []).entries()) output.write('  ' + (idx+1) + '. ' + option.label + '\n');
          output.write('Answer: ');
          return;
        }
        result = { answers };
      } else if (request.method.endsWith('requestApproval')) {
        const decision = ({ a: 'accept', d: 'decline', c: 'cancel' })[line.trim().toLowerCase()];
        if (!decision) { output.write('Use a / d / c: '); return; }
        const p = request.params ?? {};
        const mayApprove = request.method === 'item/fileChange/requestApproval'
          ? (p.proposedChanges?.length ?? 0) > 0 && p.previewComplete === true
          : !!(p.command || (p.networkApprovalContext?.host && p.networkApprovalContext?.protocol));
        if (decision === 'accept' && !mayApprove) {
          output.write('Cannot approve without reviewable details. Decline or cancel: ');
          return;
        }
        result = { decision };
      } else { output.write('Unsupported prompt type; no action taken.\n'); return; }
      socket.write(JSON.stringify({ action: 'answer', id: request.id, result }) + '\n');
      pending.shift(); answering = false; promptNext();
      return;
    }
    if (!line.trim()) return;
    socket.write(JSON.stringify({ action: 'steer', text: line }) + '\n');
  });
  rl.on('close', () => socket?.end());
  return await new Promise(resolve => socket.on('close', resolve));
}
