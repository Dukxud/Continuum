'use strict';
// Enforce dependency direction: reusable components -> platform only; Codex -> reusable.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const modules = [
  'AeroProgress',
  'Countdown',
  'SettingsStore',
  'RuntimeBundle',
  'OneTimeTasks',
  'GitRepository',
  'JobOutcomes',
  'WindowShell',
  'ProgressHost',
  'FlowingProgress',
];
const ui = [
  'legacy/winforms/CodexUiForms.ps1',
  'legacy/winforms/CodexUiSelection.ps1',
  'legacy/winforms/CodexUiPending.ps1',
  'legacy/winforms/CodexUiUsage.ps1',
  'legacy/winforms/CodexUiRefresh.ps1',
  'legacy/winforms/CodexUiActions.ps1',
  'legacy/winforms/CodexUiLifecycle.ps1',
  'legacy/winforms/CodexDashboard.ps1',
];
test('every independently importable component is explicitly manifested and Codex-free', () => {
  for (const name of modules) {
    const source = read('components/' + name + '/' + name + '.psm1');
    const manifest = read('components/' + name + '/' + name + '.psd1');
    assert.match(manifest, /RootModule\s*=/, name);
    assert.match(manifest, /FunctionsToExport\s*=/, name);
    assert.match(source, /Export-ModuleMember -Function/, name);
    assert.doesNotMatch(
      source,
      /\bCodex(?:Resume|Scheduler|Ui|Data|Usage|Retry)\b/i,
      name + ' depends on Codex',
    );
    assert.doesNotMatch(source, /\$script:ui(?:\.|\b)/, name + ' depends on UI state');
  }
});
test('worker loads no GUI, CodexData or ambient session globals', () => {
  const worker = read('src/backend/CodexRunEngine.ps1');
  const main = read('src/backend/Invoke-CodexJob.ps1');
  assert.doesNotMatch(
    worker,
    /CodexUi|CodexDashboard|System\.Windows\.Forms|\$sessionIdPattern|Get-RepositoryRoot\b/,
  );
  assert.match(worker, /Get-GitRepositoryRoot/);
  assert.match(worker, /Import-Module.+GitRepository/);
  assert.match(worker, /Import-Module.+JobOutcomes/);
  assert.doesNotMatch(main, /CodexUi|System\.Windows\.Forms|legacy[\/]/);
  assert.match(main, /Invoke-CodexScheduledJob/);
});
test('UI state ownership is explicit and cross-file categories are declared', () => {
  const groups = new Set(['Selection', 'Usage', 'Preferences', 'Dashboard', 'Async']);
  for (const file of ui) {
    const source = read(file);
    for (const match of source.matchAll(/\$script:([A-Za-z_]\w*)/g)) {
      const name = match[1];
      if (name === 'ui') {
        const rest = source.slice(match.index);
        const group = rest.match(/^\$script:ui\.([A-Za-z]+)/)?.[1];
        assert.ok(groups.has(group), file + ' references unowned UI group');
      } else {
        assert.ok(
          name === 'aeroAppearance' || name === 'aeroHealthTimer',
          file + ' uses unowned script variable ' + name,
        );
      }
    }
  }
});
test('appearance draft is owned by the Preferences context', () => {
  const state = read('legacy/winforms/CodexUiState.ps1');
  const editor = read('legacy/winforms/CodexBarAppearance.ps1');
  const actions = read('legacy/winforms/CodexUiActions.ps1');
  assert.match(state, /appearanceBeforeDraft=\$null/);
  assert.match(editor, /\$script:ui\.Preferences\.appearanceBeforeDraft = \$previous/);
  assert.match(
    actions,
    /\$appearanceForStorage = if \(\$script:ui\.Preferences\.appearanceBeforeDraft\)/,
  );
  for (const source of [editor, actions]) {
    assert.doesNotMatch(
      source,
      /\$script:appearanceBeforeDraft\b/,
      'appearance draft escapes UI Preferences ownership',
    );
  }
});
test('scheduled runtime snapshot excludes every GUI module', () => {
  const worker = read('src/backend/CodexRunEngine.ps1');
  const runtime = worker.match(/function Get-CodexRuntimeFiles\s*\{([\s\S]*?)\n\}/)?.[1];
  assert.ok(runtime, 'runtime dependency manifest missing');
  for (const file of [
    'src/backend/Invoke-CodexJob.ps1',
    'src/backend/CodexRunEngine.ps1',
    'src/backend/CodexUsage.js',
    'components/RuntimeBundle/RuntimeBundle.psm1',
    'components/GitRepository/GitRepository.psm1',
    'components/JobOutcomes/JobOutcomes.psm1',
    'components/SettingsStore/SettingsStore.psm1',
  ]) {
    assert.ok(runtime.includes("'" + file + "'"), 'worker missing ' + file);
  }
  assert.doesNotMatch(
    runtime,
    /legacy|CodexUiForms|CodexUiState|CodexDashboard|CodexData|AeroBar\.html/,
  );
});

test('pending jobs never mix with result histories and countdowns do not scan pending list for every row', () => {
  const data = read('src/backend/CodexData.ps1'),
    store = read('src/backend/CodexJobStore.ps1'),
    dash = read('legacy/winforms/CodexDashboard.ps1');
  assert.match(data, /Get-CodexJobPayloadFiles/);
  assert.match(store, /\.result\\\.json/);
  assert.match(store, /Get-CodexRunHistory/);
  assert.match(dash, /pendingIndex/);
  assert.doesNotMatch(dash, /pendingSnapshot\s*\|\s*Where-Object/);
});
test('run history remains user-visible without retry scheduling', () => {
  assert.match(read('legacy/winforms/CodexUiForms.ps1'), /\$recentResults = Add-Button/);
  assert.match(read('legacy/winforms/CodexUiActions.ps1'), /Show-CodexRunHistoryDialog/);
  assert.doesNotMatch(read('src/backend/CodexRunEngine.ps1'), /Schedule-LimitRetry|CodexRetry/);
  // Historic deferred results remain readable after removing retry authoring.
  assert.match(read('src/backend/CodexJobStore.ps1'), /Get-CodexRunHistory/);
});

test('cancellation rechecks authoritative Windows state before unregistering', () => {
  const generic = read('components/OneTimeTasks/OneTimeTasks.psm1');
  const ui = read('legacy/winforms/CodexUiActions.ps1');
  assert.match(generic, /function Remove-OneTimeTask/);
  assert.match(generic, /\[switch\]\$OnlyBeforeStart/);
  assert.match(generic, /Get-ScheduledTask -TaskName \$Name/);
  assert.match(generic, /Get-ScheduledTaskInfo -TaskName \$Name/);
  assert.match(ui, /Remove-OneTimeTask -Name \$name -OnlyBeforeStart/);
});
test('WinForms acceptance cannot silently ignore UI-thread exceptions', () => {
  const harness = read('tests/WinFormsEventGuard.ps1');
  assert.match(harness, /add_ThreadException/);
  assert.match(harness, /throw \('Unhandled Windows Forms event exceptions/);
  for (const name of [
    'aero-appearance-dialog',
    'aero-runtime-fallback',
    'aero-webview-rendering',
    'dashboard-layout',
    'dashboard-visuals',
    'history-dialog',
    'second-application-reuse',
    'standalone-aero-consumer',
    'wpf-flow-animation',
  ]) {
    const source = read('tests/' + name + '.test.ps1');
    assert.match(source, /WinFormsEventGuard.ps1/);
    assert.match(source, /Assert-NoUnhandledWinFormsErrors/);
  }
});
test('model catalog and async jobs have single state-owning controllers', () => {
  const selection = read('legacy/winforms/CodexUiSelection.ps1');
  const usage = read('legacy/winforms/CodexUiUsage.ps1');
  const asyncDispatcher = read('legacy/winforms/CodexUiRefresh.ps1');
  assert.match(selection, /function Apply-CodexModelCatalog/);
  assert.match(usage, /Apply-CodexModelCatalog -Snapshot \$Snapshot/);
  assert.doesNotMatch(
    usage,
    /\$script:ui\.Selection\.[a-zA-Z]+\s*=/,
    'usage controller must not mutate selection-owned state',
  );
  assert.doesNotMatch(asyncDispatcher, /\$script:ui\.Selection\.data(?:Jobs|Queued)/);
  assert.match(asyncDispatcher, /\$script:ui\.Async\.dataJobs/);
});

test('one scheduling-eligibility owner enforces fresh model and workspace authority', () => {
  const selection = read('legacy/winforms/CodexUiSelection.ps1');
  const usage = read('legacy/winforms/CodexUiUsage.ps1');
  const dashboard = read('legacy/winforms/CodexDashboard.ps1');
  const actions = read('legacy/winforms/CodexUiActions.ps1');
  assert.match(selection, /function Update-SchedulingEligibility/);
  assert.match(selection, /usageReadFailed/);
  assert.match(selection, /usageSnapshotReceivedAt/);
  assert.match(selection, /usageProcess/);
  assert.match(selection, /usageRefreshQueued/);
  assert.match(selection, /usageSnapshotRequestedModel/);
  assert.match(selection, /Test-CanonicalWorkspaceIdentity/);
  assert.match(usage, /Update-SchedulingEligibility/);
  assert.match(usage, /usageSnapshotReceivedAt = Get-Date/);
  assert.match(read('legacy/winforms/CodexUiLifecycle.ps1'), /Update-SchedulingEligibility/);
  assert.match(usage, /\$script:ui\.Usage\.usageSnapshot = \$null/);
  assert.doesNotMatch(usage, /\$schedule\.Enabled\s*=/);
  assert.doesNotMatch(actions, /\$schedule\.Enabled\s*=/);
  assert.match(actions, /Update-SchedulingEligibility\s*\n\s*if \(-not \$schedule\.Enabled\)/);
  assert.match(dashboard, /Request-SystemRefresh -Scope ModelChanged/);
  assert.doesNotMatch(dashboard, /Request-UsageRefresh/);
});

test('transcript cleanup cannot override the worker exit status', () => {
  const worker = read('src/backend/CodexRunEngine.ps1');
  assert.match(worker, /try \{ Stop-Transcript -ErrorAction Stop \| Out-Null \}/);
  assert.match(worker, /catch \{ Write-Warning "Worker transcript could not be closed:/);
  assert.match(worker, /catch \{ Write-Warning "Worker session lock could not be released:/);
  assert.match(worker, /catch \{ Write-Warning "Worker session lock could not be disposed:/);
});

test('all scheduled executions must bind to a verified selected workspace', () => {
  const ui = read('legacy/winforms/CodexUiActions.ps1'),
    worker = read('src/backend/CodexRunEngine.ps1');
  assert.match(ui, /Test-CanonicalWorkspaceIdentity \$accountId/);
  assert.match(ui, /accountId=\$accountId/);
  assert.match(worker, /function Test-CanonicalWorkspaceIdentity/);
  assert.match(worker, /Test-CanonicalWorkspaceIdentity \(\[string\]\$job.accountId\)/);
  assert.match(worker, /\$state = Read-UsageState \$model/);
  assert.match(worker, /scheduled execution refused/);
});
