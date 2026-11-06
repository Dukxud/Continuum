import { readFile } from 'node:fs/promises';
import { dirname, basename, isAbsolute } from 'node:path';
import { SharedSessionHost, locationFor } from './host.mjs';
import { connectToSession, terminalWatch } from './client.mjs';

const [mode, jobPath, codexEntry] = process.argv.slice(2);
if (!['host', 'watch', 'status', 'answer'].includes(mode) || !isAbsolute(jobPath)) {
  console.error('Usage: node main.mjs <host|watch|status|answer> ABSOLUTE_JOB_JSON [ABSOLUTE_CODEX_CLI_JS]');
  process.exit(2);
}
const jobName = basename(jobPath, '.json');
const appDir = dirname(jobPath);
const { descriptor } = locationFor(appDir, jobName);
async function run() {
  if (mode === 'host') {
    const job = JSON.parse(await readFile(jobPath, 'utf8'));
    const host = new SharedSessionHost({ job, jobName, appDir, codexEntry });
    const quit = () => { host.fatal(new Error('Session host terminated')); };
    process.once('SIGINT', quit);
    process.once('SIGTERM', quit);
    try {
      const outcome = await host.begin();
      if (outcome !== 'completed') { console.error('Codex turn ended: ' + outcome); process.exitCode = 1; }
      else console.log('Codex turn completed.');
    } finally { await host.close(); }
  } else if (mode === 'watch') {
    await terminalWatch(descriptor);
  } else if (mode === 'status') {
    let socket;
    socket = await connectToSession(descriptor, msg => {
      if (msg.action === 'snapshot') { process.stdout.write(JSON.stringify(msg) + '\n'); socket.end(); }
    });
  } else {
    // Approval bodies arrive on stdin, never command arguments or process lists.
    const line = await new Promise(resolve => {
      let value = '';
      process.stdin.setEncoding('utf8');
      process.stdin.on('data', d => { value += d; if (value.includes('\n')) resolve(value.split('\n')[0]); });
      process.stdin.on('end', () => resolve(value));
    });
    const command = JSON.parse(line);
    let socket;
    socket = await connectToSession(descriptor, msg => {
      if (msg.action === 'snapshot') socket.write(JSON.stringify(command) + '\n');
      if (['ack','error'].includes(msg.action)) {
        console.log(JSON.stringify(msg)); socket.end();
        if (msg.action === 'error') process.exitCode = 1;
      }
    });
  }
}
run().catch(error => { console.error(error.message); process.exitCode = 1; });
