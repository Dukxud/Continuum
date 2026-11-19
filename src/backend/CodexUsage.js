#!/usr/bin/env node
'use strict';
// Codex App Server account/rateLimits/read and model/list. No login file access.
const { spawn } = require('node:child_process');
const readline = require('node:readline');
const path = require('node:path');
const fs = require('node:fs');
const { createHash } = require('node:crypto');
const { createRequire } = require('node:module');

function codexAppServerCommand(entry) {
  const extension = path.extname(entry).toLowerCase();
  if (!path.isAbsolute(entry) || !fs.statSync(entry).isFile())
    throw new Error('Codex entry must be an existing absolute file.');
  if (extension !== '.js') {
    if (extension && extension !== '.exe')
      throw new Error('Codex native entry must be an executable, not a shell shim.');
    return { executable: entry, args: [], env: process.env };
  }
  // Official npm installs contain a native binary. Use it directly so Windows
  // does not interpose a Node wrapper between us and the protocol process.
  // Unknown/older package layouts retain the supported JavaScript entry path.
  try {
    const packageRoot = fs.realpathSync(path.join(path.dirname(entry), '..'));
    const metadata = JSON.parse(fs.readFileSync(path.join(packageRoot, 'package.json'), 'utf8'));
    const targets = {
      'win32-x64': 'x86_64-pc-windows-msvc',
      'win32-arm64': 'aarch64-pc-windows-msvc',
      'linux-x64': 'x86_64-unknown-linux-musl',
      'linux-arm64': 'aarch64-unknown-linux-musl',
      'darwin-x64': 'x86_64-apple-darwin',
      'darwin-arm64': 'aarch64-apple-darwin',
    };
    const platform = `${process.platform}-${process.arch}`;
    const target = targets[platform];
    if (metadata.name === '@openai/codex' && target) {
      const vendors = [];
      try {
        const installed = createRequire(entry).resolve(`@openai/codex-${platform}/package.json`);
        vendors.push(path.join(path.dirname(installed), 'vendor'));
      } catch {}
      vendors.push(path.join(packageRoot, 'vendor'));
      const binary = process.platform === 'win32' ? 'codex.exe' : 'codex';
      for (const vendor of vendors) {
        for (const folder of ['bin', 'codex']) {
          const executable = path.join(vendor, target, folder, binary);
          if (fs.existsSync(executable) && fs.statSync(executable).isFile())
            return {
              executable,
              args: [],
              env: { ...process.env, CODEX_MANAGED_PACKAGE_ROOT: packageRoot },
            };
        }
      }
    }
  } catch {}
  return { executable: process.execPath, args: [entry], env: process.env };
}

function startCodexAppServer(entry) {
  const command = codexAppServerCommand(entry);
  const child = spawn(command.executable, [...command.args, 'app-server', '--listen', 'stdio://'], {
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsHide: true,
    env: command.env,
    // A private process group lets Unix clean up this child's descendants
    // without matching names or affecting another Codex process.
    detached: process.platform !== 'win32',
  });
  let closed = false,
    stopping = null;
  const close = new Promise((resolve) =>
    child.once('close', () => {
      closed = true;
      resolve();
    }),
  );
  const stop = () => {
    if (stopping) return stopping;
    stopping = new Promise((resolve, reject) => {
      if (closed) return resolve();
      let force,
        treeKiller,
        cleanupError = null;
      const killGroup = (signal) => {
        try {
          if (child.pid) process.kill(-child.pid, signal);
        } catch (error) {
          if (error.code !== 'ESRCH') cleanupError = error;
        }
      };
      // Close input first. Killing a Windows npm Node wrapper immediately can
      // orphan its native child, which still owns stdout/stderr pipe handles.
      child.stdin.on('error', () => {});
      child.stdin.end();
      const grace = setTimeout(() => {
        if (closed || !child.pid) return;
        if (process.platform === 'win32') {
          // Do not target a stale/reusable PID if a nonstandard launcher exited
          // independently while a descendant retained its pipe handles.
          if (child.exitCode !== null || child.signalCode !== null) {
            cleanupError = new Error('Codex launcher exited before its process tree closed.');
            return;
          }
          const taskkill = path.join(
            process.env.SystemRoot || 'C:\\Windows',
            'System32',
            'taskkill.exe',
          );
          treeKiller = spawn(taskkill, ['/PID', String(child.pid), '/T', '/F'], {
            stdio: 'ignore',
            windowsHide: true,
          });
          treeKiller.once('error', (error) => (cleanupError = error));
          treeKiller.once('close', (code) => {
            if (code && !closed) cleanupError = new Error('Codex process-tree cleanup failed.');
          });
        } else {
          killGroup('SIGTERM');
          force = setTimeout(() => killGroup('SIGKILL'), 250);
        }
      }, 750);
      const deadline = setTimeout(() => {
        clearTimeout(grace);
        clearTimeout(force);
        treeKiller?.kill();
        child.stdin.destroy();
        child.stdout.destroy();
        child.stderr.destroy();
        child.unref();
        reject(cleanupError || new Error('Codex App Server process did not close after shutdown.'));
      }, 2500);
      close.then(() => {
        clearTimeout(grace);
        clearTimeout(force);
        clearTimeout(deadline);
        resolve();
      });
    });
    return stopping;
  };
  return { child, stop };
}

const validEpoch = (n) => (Number.isSafeInteger(n) && n > 0 ? n : null);
function describeWindow(w, slot) {
  if (!w || typeof w !== 'object') return null;
  const d = w.windowDurationMins;
  const label =
    d === 300 ? '5-hour' : d === 10080 ? 'Weekly' : Number.isFinite(d) ? `${d}-minute` : slot;
  const pct = Number.isFinite(w.usedPercent) ? w.usedPercent : null;
  return {
    label,
    usedPercent: pct,
    remainingPercent: pct === null ? null : Math.max(0, Math.min(100, 100 - pct)),
    resetsAt: validEpoch(w.resetsAt),
  };
}
function normalizeModels(pages) {
  const seen = new Set();
  return pages
    .flatMap((page) => (Array.isArray(page.data) ? page.data : []))
    .filter((m) => {
      const id = m?.model || m?.id;
      if (typeof id !== 'string' || !id || seen.has(id) || m.hidden === true) return false;
      seen.add(id);
      return true;
    })
    .map((m) => ({
      id: m.model || m.id,
      name: m.displayName || m.model || m.id,
      defaultEffort: m.defaultReasoningEffort || null,
      isDefault: m.isDefault === true,
      efforts: Array.isArray(m.supportedReasoningEfforts)
        ? [
            ...new Set(
              m.supportedReasoningEfforts
                .map((e) => e?.reasoningEffort)
                .filter((e) => typeof e === 'string' && e && e !== 'ultra'),
            ),
          ]
        : [],
    }));
}
// Rate-limit accountId may be absent. account/read can supply a ChatGPT email;
// hash it rather than storing or logging the address.
function identifyAccount(rateResult, accountResult) {
  // Only backend-selected workspace IDs establish safe unattended identity.
  // Email identifies a person, not the currently selected ChatGPT workspace.
  const id = (value) =>
    typeof value === 'string' && value.trim().length > 0 && value.trim().length <= 256
      ? value.trim()
      : null;
  const rateId = id(rateResult?.accountId);
  const routingId = id(accountResult?.workspaceRouting?.chatgptAccountId);
  if (rateId && routingId && rateId !== routingId) {
    return { accountId: null, accountIdentitySource: null, accountIdentityStatus: 'conflict' };
  }
  const workspaceId = routingId || rateId;
  if (!workspaceId) {
    return { accountId: null, accountIdentitySource: null, accountIdentityStatus: 'unavailable' };
  }
  // Same canonical value regardless of which endpoint supplies the ID.
  // Neither the raw workspace ID nor a person's email is persisted.
  const hash = createHash('sha256')
    .update('codex-workspace-v1:' + workspaceId)
    .digest('hex');
  return {
    accountId: 'workspace-sha256:' + hash,
    accountIdentitySource: routingId ? 'workspace-routing' : 'rate-limits-id',
    accountIdentityStatus: 'verified',
  };
}
function selectBucket(result, model) {
  const byId = result.rateLimitsByLimitId;
  const buckets =
    byId && typeof byId === 'object'
      ? Object.entries(byId).filter(([, v]) => v && typeof v === 'object')
      : [];
  if (!buckets.length) {
    const rate = result.rateLimits;
    return rate && (!model || !rate.normalModelSlug || rate.normalModelSlug === model)
      ? { id: rate.limitId || 'default', rate, verified: true }
      : null;
  }
  if (buckets.length === 1) {
    const [id, rate] = buckets[0];
    if (model && rate.normalModelSlug && rate.normalModelSlug !== model) return null;
    return { id, rate, verified: true };
  }
  if (!model) return null;
  const matches = buckets.filter(([id, b]) => [id, b.limitId, b.normalModelSlug].includes(model));
  return matches.length === 1 ? { id: matches[0][0], rate: matches[0][1], verified: true } : null;
}
function summarizeRateLimits(result, now = Math.floor(Date.now() / 1000), model = null) {
  const selected = selectBucket(result, model);
  const ordinaryUsageAllowed =
    typeof result.ordinaryUsageAllowed === 'boolean' ? result.ordinaryUsageAllowed : null;
  if (!selected)
    return {
      ok: true,
      ordinaryUsageAllowed,
      model,
      bucketId: null,
      selectionVerified: false,
      checkedAt: new Date(now * 1000).toISOString(),
      accountId: result.accountId || null,
      windows: [],
      limitReachedType: null,
      recommendedResetAt: null,
      recommendationKind: null,
      canAttempt: false,
      blockedReason: 'Quota bucket cannot be attributed to the selected model.',
    };
  const rate = selected.rate;
  const windows = [
    describeWindow(rate.primary, 'Primary'),
    describeWindow(rate.secondary, 'Secondary'),
  ].filter(Boolean);
  const exhausted = windows.filter((w) => w.usedPercent !== null && w.usedPercent >= 100);
  const isBlocked =
    ordinaryUsageAllowed === false ||
    exhausted.length > 0 ||
    !!rate.rateLimitReachedType ||
    rate.spendControlReached === true;
  const resetKnown =
    exhausted.length > 0 && exhausted.every((w) => w.resetsAt !== null && w.resetsAt > now);
  const recommendedResetAt =
    isBlocked &&
    resetKnown &&
    rate.spendControlReached !== true &&
    (!rate.rateLimitReachedType || rate.rateLimitReachedType === 'rate_limit_reached')
      ? Math.max(...exhausted.map((w) => w.resetsAt))
      : null;
  const canAttempt = ordinaryUsageAllowed === true && !isBlocked;
  const future = windows.filter((w) => w.resetsAt !== null && w.resetsAt > now);
  const nextReset = !isBlocked && future.length ? Math.min(...future.map((w) => w.resetsAt)) : null;
  return {
    ok: true,
    checkedAt: new Date(now * 1000).toISOString(),
    model,
    bucketId: selected.id,
    selectionVerified: true,
    ordinaryUsageAllowed,
    accountId: result.accountId || null,
    limitReachedType: rate.rateLimitReachedType || null,
    windows,
    recommendedResetAt: recommendedResetAt ?? nextReset,
    recommendationKind:
      recommendedResetAt !== null ? 'exhausted-window' : nextReset !== null ? 'next-window' : null,
    canAttempt,
    blockedReason:
      !isBlocked && ordinaryUsageAllowed !== true
        ? 'Backend usage permission unavailable.'
        : isBlocked && recommendedResetAt === null
          ? 'Usage restricted; no reliable applicable reset time.'
          : null,
  };
}
function readCodexState(
  cliJs,
  { model = null, timeoutMs = 18000, catalog = true, modelsOnly = false, threadId = null } = {},
) {
  return new Promise((resolve, reject) => {
    const { child, stop } = startCodexAppServer(cliJs);
    let settled = false,
      stderr = '',
      pages = [],
      catalogError = null,
      requestId = 1,
      stage = 'initialize',
      account = null;
    const lines = readline.createInterface({ input: child.stdout });
    const timer = setTimeout(
      () => finish(new Error('Codex App Server request timed out.')),
      timeoutMs,
    );
    function finish(err, result) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      lines.close();
      stop().then(() => {
        if (err) reject(err);
        else resolve(result);
      }, reject);
    }
    function send(data) {
      if (!settled) child.stdin.write(JSON.stringify(data) + '\n');
    }
    function requestModels(cursor = null) {
      stage = 'models';
      requestId++;
      const params = { limit: 100, includeHidden: false };
      if (cursor) params.cursor = cursor;
      send({ id: requestId, method: 'model/list', params });
    }
    function requestRate() {
      stage = 'rate';
      requestId++;
      send({ id: requestId, method: 'account/rateLimits/read' });
    }
    function requestAccount() {
      stage = 'account';
      requestId++;
      send({ id: requestId, method: 'account/read', params: { refreshToken: false } });
    }
    function requestThread() {
      stage = 'thread';
      requestId++;
      send({ id: requestId, method: 'thread/read', params: { threadId, includeTurns: false } });
    }
    child.on('error', (e) => finish(e));
    child.stdin.on('error', (e) => finish(e));
    child.on('close', (code) => {
      if (!settled) finish(new Error(`Codex App Server exited (${code}). ${stderr.slice(-150)}`));
    });
    child.stderr.on('data', (p) => {
      stderr = (stderr + p.toString()).slice(-500);
    });
    lines.on('line', (line) => {
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        return;
      }
      if (msg.id !== requestId) return;
      if (stage === 'initialize') {
        if (msg.error) return finish(new Error(msg.error.message || 'Initialization failed'));
        send({ method: 'initialized', params: {} });
        if (threadId) requestThread();
        else if (modelsOnly) requestModels();
        else requestAccount();
      } else if (stage === 'account') {
        // Use account/read only for identity; its failure does not erase a
        // verified accountId delivered by account/rateLimits/read.
        if (!msg.error && msg.result && typeof msg.result === 'object') account = msg.result;
        if (catalog) requestModels();
        else requestRate();
      } else if (stage === 'thread') {
        if (msg.error) return finish(new Error(msg.error.message || 'Thread metadata unavailable'));
        try {
          finish(null, normalizeThreadRead(msg.result, threadId));
        } catch (e) {
          finish(e);
        }
      } else if (stage === 'models') {
        if (msg.error) catalogError = msg.error.message || 'Model catalog unavailable';
        else {
          pages.push(msg.result || {});
          const cursor = msg.result?.nextCursor;
          if (typeof cursor === 'string' && cursor && pages.length < 20)
            return requestModels(cursor);
          if (typeof cursor === 'string' && cursor)
            catalogError = 'Model catalog pagination exceeded 20 pages.';
        }
        if (modelsOnly) {
          if (catalogError) return finish(new Error(catalogError));
          return finish(null, { ok: true, models: normalizeModels(pages) });
        }
        requestRate();
      } else if (stage === 'rate') {
        if (msg.error)
          return finish(new Error(msg.error.message || 'Codex rate-limit request rejected'));
        try {
          const models = normalizeModels(pages);
          const chosen =
            model ||
            models.find((m) => m.isDefault)?.id ||
            (models.length === 1 ? models[0].id : null);
          const summary = summarizeRateLimits(
            msg.result || {},
            Math.floor(Date.now() / 1000),
            chosen,
          );
          const identity = identifyAccount(msg.result, account);
          finish(null, { ...summary, ...identity, models, catalogError });
        } catch (e) {
          finish(e);
        }
      }
    });
    send({
      id: requestId,
      method: 'initialize',
      params: {
        clientInfo: {
          name: 'codex_resume_scheduler',
          title: 'Codex Resume Scheduler',
          version: '1.16.0',
        },
        capabilities: { experimentalApi: true },
      },
    });
  });
}
function readRateLimits(cliJs, timeoutMs = 18000) {
  return readCodexState(cliJs, { timeoutMs, catalog: false });
}
function normalizeThreadSource(source) {
  // Only omitted/null sources are eligible for legacy local-header fallback.
  // Codex also returns structured custom and subAgent variants; collapsing an
  // explicit unsupported source to null would let stale CLI evidence win.
  if (source == null) return null;
  if (typeof source === 'string') return source.trim() || 'unknown';
  if (typeof source === 'object' && !Array.isArray(source)) {
    if (Object.prototype.hasOwnProperty.call(source, 'custom')) return 'custom';
    if (Object.prototype.hasOwnProperty.call(source, 'subAgent')) return 'subAgent';
  }
  return 'unknown';
}
function normalizeThreadRead(result, expectedId) {
  const thread = result?.thread;
  if (!thread || thread.id !== expectedId)
    throw new Error('Codex returned unexpected thread metadata.');
  const text = (value) => (typeof value === 'string' && value.trim() ? value.trim() : null);
  // thread/read does not resume a conversation or subscribe to turns.
  const cwd = text(thread.cwd);
  // Use the Codex-owned title, not a guessed title from rollout messages.
  // thread/read is a metadata-only operation (includeTurns is false).
  const name = text(thread.name);
  const preview = text(thread.preview);
  // A persisted thread can have a compressed or reference-backed rollout.
  // Keep Codex's exact metadata rather than requiring a readable JSONL first.
  // These are discovery hints; callers still verify every local Git root.
  const git = thread.gitInfo;
  const gitInfo =
    git && typeof git === 'object'
      ? { originUrl: text(git.originUrl), branch: text(git.branch), sha: text(git.sha) }
      : null;
  return {
    ok: true,
    threadId: expectedId,
    cwd,
    name,
    preview,
    source: normalizeThreadSource(thread.source),
    path: text(thread.path),
    updatedAt: validEpoch(thread.updatedAt),
    gitInfo,
  };
}
function readThreadDirectory(cliJs, threadId, timeoutMs = 10000) {
  if (
    typeof threadId !== 'string' ||
    !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(threadId)
  )
    return Promise.reject(new Error('Invalid Codex conversation ID.'));
  return readCodexState(cliJs, { threadId, timeoutMs, catalog: false });
}
// One App Server process for the chooser, never one per conversation.
// Requests are independent and bounded; an inaccessible thread cannot block
// the titles of other sessions or the essential load path.
function readThreadSummaries(cliJs, threadIds, timeoutMs = 12000) {
  const valid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
  if (
    !Array.isArray(threadIds) ||
    threadIds.length > 30 ||
    threadIds.some((id) => typeof id !== 'string' || !valid.test(id))
  )
    return Promise.reject(new Error('Invalid thread summary request.'));
  if (!threadIds.length) return Promise.resolve({ ok: true, threads: {}, partial: false });
  return readThreadMetadata(cliJs, { threadIds, timeoutMs });
}

// Codex owns the current rollout path and can read compressed histories. The
// local filesystem remains a fallback in PowerShell, not the entire inventory.
function readRecentCliThreads(cliJs, timeoutMs = 12000) {
  return readThreadMetadata(cliJs, { timeoutMs, inventory: true });
}

function readThreadMetadata(cliJs, { threadIds = [], timeoutMs, inventory = false }) {
  const valid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
  const wanted = new Set(threadIds);
  return new Promise((resolve, reject) => {
    const { child, stop } = startCodexAppServer(cliJs);
    const lines = readline.createInterface({ input: child.stdout });
    const threads = {};
    const sessions = [];
    const seenThreads = new Set();
    const seenCursors = new Set();
    const reads = new Map();
    let settled = false,
      initialized = false,
      stderr = '',
      requestId = 1,
      pages = 0,
      listRequestId = null,
      listTimer = null,
      reading = false,
      readQueue = [];
    const result = (partial) =>
      inventory ? { ok: true, sessions, partial } : { ok: true, threads, partial: wanted.size > 0 };
    const timer = setTimeout(() => finish(null, result(true)), timeoutMs);
    function finish(error, value) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearTimeout(listTimer);
      for (const entry of reads.values()) clearTimeout(entry.timer);
      lines.close();
      stop().then(() => {
        if (error) reject(error);
        else resolve(value);
      }, reject);
    }
    function send(message) {
      if (!settled) child.stdin.write(JSON.stringify(message) + '\n');
    }
    function requestPage(cursor = null) {
      pages++;
      requestId++;
      listRequestId = requestId;
      const params = {
        limit: inventory ? 30 : 100,
        sourceKinds: ['cli', 'exec'],
        archived: false,
        sortKey: 'updated_at',
      };
      if (cursor) params.cursor = cursor;
      send({ id: requestId, method: 'thread/list', params });
    }
    function finishListing(partial = false) {
      if (inventory) return finish(null, result(partial));
      if (reading || settled) return;
      clearTimeout(listTimer);
      listRequestId = null;
      reading = true;
      readQueue = [...wanted];
      requestReads();
    }
    function requestReads() {
      if (settled) return;
      // One metadata process, at most four in-flight exact reads and one attempt
      // per missing ID. A stuck thread cannot consume the entire chooser budget.
      while (reads.size < 4 && readQueue.length) {
        const threadId = readQueue.shift();
        const id = ++requestId;
        const entry = {
          threadId,
          timer: setTimeout(
            () => {
              reads.delete(id);
              requestReads();
            },
            Math.min(2000, Math.max(50, Math.floor(timeoutMs / 2))),
          ),
        };
        reads.set(id, entry);
        send({ id, method: 'thread/read', params: { threadId, includeTurns: false } });
      }
      if (!reads.size && !readQueue.length) finish(null, result(wanted.size > 0));
    }
    child.on('error', (error) => finish(error));
    child.stdin.on('error', (error) => finish(error));
    child.on('close', (code) => {
      if (!settled)
        finish(new Error('Codex App Server exited (' + code + '). ' + stderr.slice(-120)));
    });
    child.stderr.on('data', (chunk) => {
      stderr = (stderr + chunk.toString()).slice(-300);
    });
    lines.on('line', (line) => {
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        return;
      }
      if (!initialized) {
        if (msg.id !== 1) return;
        if (msg.error) return finish(new Error(msg.error.message || 'Initialization failed.'));
        initialized = true;
        send({ method: 'initialized', params: {} });
        // Reserve time for selected IDs that lie beyond the list's bounded
        // pages, or when an optional listing stalls. Inventory has no known IDs.
        if (!inventory)
          listTimer = setTimeout(() => finishListing(true), Math.floor(timeoutMs / 2));
        requestPage();
        return;
      }
      if (reading) {
        const entry = reads.get(msg.id);
        if (!entry) return;
        clearTimeout(entry.timer);
        reads.delete(msg.id);
        if (!msg.error) {
          try {
            // Never overwrite a list-derived name with a possibly stale read.
            threads[entry.threadId] = normalizeThreadRead(msg.result, entry.threadId);
            wanted.delete(entry.threadId);
          } catch {
            // Wrong identity or malformed metadata remains unresolved.
          }
        }
        requestReads();
        return;
      }
      if (msg.id !== listRequestId) return;
      if (msg.error) {
        if (inventory && pages === 1)
          return finish(new Error(msg.error.message || 'Codex thread listing failed.'));
        return finishListing(true);
      }
      const page = msg.result || {};
      for (const thread of Array.isArray(page.data) ? page.data : []) {
        if (!thread || typeof thread.id !== 'string' || !valid.test(thread.id)) continue;
        if (inventory) {
          if (!['cli', 'exec'].includes(thread.source) || seenThreads.has(thread.id)) continue;
          seenThreads.add(thread.id);
          sessions.push(normalizeThreadRead({ thread }, thread.id));
          if (sessions.length === 30) return finish(null, result(false));
        } else if (wanted.has(thread.id)) {
          threads[thread.id] = normalizeThreadRead({ thread }, thread.id);
          wanted.delete(thread.id);
        }
      }
      const cursor = page.nextCursor;
      if (!inventory && !wanted.size) return finish(null, result(false));
      if (!cursor) return finishListing(false);
      if (typeof cursor !== 'string' || seenCursors.has(cursor) || pages >= 6)
        return finishListing(true);
      seenCursors.add(cursor);
      requestPage(cursor);
    });
    send({
      id: 1,
      method: 'initialize',
      params: {
        clientInfo: {
          name: 'codex_resume_scheduler',
          title: 'Codex Resume Scheduler',
          version: '1.16.0',
        },
        capabilities: { experimentalApi: true },
      },
    });
  });
}
async function main() {
  const jsFlag = process.argv.indexOf('--cli-js');
  const exeFlag = process.argv.indexOf('--cli-exe');
  if (jsFlag >= 0 && exeFlag >= 0) throw new Error('Specify exactly one Codex entry.');
  const flag = exeFlag >= 0 ? exeFlag : jsFlag;
  const cliJs = flag >= 0 ? process.argv[flag + 1] : null;
  if (!cliJs || !fs.existsSync(cliJs)) throw new Error('Codex CLI entry not found.');
  const extension = path.extname(cliJs).toLowerCase();
  if (exeFlag >= 0 && (!path.isAbsolute(cliJs) || (extension && extension !== '.exe')))
    throw new Error('Codex native entry must be an absolute executable, not a shell shim.');
  if (jsFlag >= 0 && extension !== '.js') throw new Error('Codex npm CLI entry not found.');
  const modelFlag = process.argv.indexOf('--model');
  const model = modelFlag >= 0 ? process.argv[modelFlag + 1] : null;
  const threadFlag = process.argv.indexOf('--thread-id');
  const threadId = threadFlag >= 0 ? process.argv[threadFlag + 1] : null;
  const threadsFlag = process.argv.indexOf('--thread-ids');
  const state = process.argv.includes('--sessions')
    ? await readRecentCliThreads(path.resolve(cliJs))
    : threadsFlag >= 0
      ? await readThreadSummaries(
          path.resolve(cliJs),
          (process.argv[threadsFlag + 1] || '').split(',').filter(Boolean),
        )
      : threadFlag >= 0
        ? await readThreadDirectory(path.resolve(cliJs), threadId)
        : await readCodexState(path.resolve(cliJs), {
            model,
            catalog: !process.argv.includes('--rates-only'),
            modelsOnly: process.argv.includes('--models-only'),
          });
  process.stdout.write(JSON.stringify(state) + '\n');
}
if (require.main === module)
  main().catch((e) => {
    process.stdout.write(JSON.stringify({ ok: false, error: e.message }) + '\n');
    process.exitCode = 1;
  });
module.exports = {
  codexAppServerCommand,
  describeWindow,
  normalizeModels,
  selectBucket,
  summarizeRateLimits,
  readCodexState,
  readRateLimits,
  normalizeThreadRead,
  readThreadDirectory,
  readThreadSummaries,
  readRecentCliThreads,
  identifyAccount,
};
