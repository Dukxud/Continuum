'use strict';
// These checks protect the Windows Forms presentation contract. They do not
// replace a live GUI test on Windows at different display scaling settings.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = ['legacy/winforms/CodexUiForms.ps1','legacy/winforms/CodexUiSelection.ps1','legacy/winforms/CodexUiPending.ps1','legacy/winforms/CodexUiUsage.ps1','legacy/winforms/CodexUiRefresh.ps1','legacy/winforms/CodexUiActions.ps1'].map(f=>fs.readFileSync(path.resolve(__dirname, '..', f),'utf8')).join('\n');
function namedFunction(name) {
  const begin = source.indexOf(`function ${name} {`);
  assert.ok(begin >= 0, `${name} should exist`);
  const nextFunction = source.indexOf('\nfunction ', begin + 10);
  const nextSection = source.indexOf('\n$dataPoll', begin + 10);
  const ends = [nextFunction, nextSection].filter(i => i >= 0);
  return source.slice(begin, ends.length ? Math.min(...ends) : undefined);
}

test('model and effort are grouped and schedule action is distinct', () => {
  assert.match(source, /New-DesktopWindow -Title 'Codex Resume Scheduler v1\.[0-9]+\.[0-9]+'/);
  assert.match(source, /\$modelBox\.Location = \[System\.Drawing\.Point\]::new\(90,199\)/);
  assert.match(source, /\$effortBox\.Location = \[System\.Drawing\.Point\]::new\(450,199\)/);
  assert.match(source, /\$accessBox\.Location = \[System\.Drawing\.Point\]::new\(652,199\)/);
  assert.match(source, /\$schedule = Add-Button 'Schedule once' 720 274 178/);
  assert.doesNotMatch(source, /\$autoResumeCheck|Retry if Codex/);
  assert.match(source, /\$whenBox\.Value = Get-CodexSuggestedRunTime/);
  assert.match(source, /\$minusTime = Add-Button '−' 155 154 38/);
  assert.match(source, /\$whenBox\.Location = \[System\.Drawing\.Point\]::new\(202,154\)/);
  assert.match(source, /\$plusTime = Add-Button '\+' 446 154 38/);
  assert.match(source, /\$minusTime = Add-Button/);
  assert.match(source, /\$plusTime = Add-Button/);
  assert.match(source, /\$minusTime\.Add_Click/);
  assert.match(source, /\$plusTime\.Add_Click/);
  const now=source.match(/\$nowPlusTwo = Add-Button 'Now \+2' (\d+) (\d+) (\d+)/);
  const reset=source.match(/\$useReset = Add-Button 'Reset \+2' (\d+) (\d+) (\d+)/);
  assert.ok(now&&reset,'Both scheduling shortcuts must exist');
  const [nowX,nowY,nowW]=now.slice(1).map(Number);
  const [resetX,resetY,resetW]=reset.slice(1).map(Number);
  assert.equal(nowY,resetY,'Shortcuts must share a row');
  assert.ok(resetX >= nowX+nowW+12,'Shortcuts must have at least 12px separation');
  assert.equal(resetX+resetW,898,'Shortcut group must align with the main form right edge');
  assert.match(source, /\$nowPlusTwo\.Add_Click/);
  assert.match(source, /\$useReset\.Add_Click/);
});

test('normal scheduling has no redundant success dialog, but preserves safety warnings', () => {
  const schedule = source.slice(source.indexOf('$schedule.Add_Click({'));
  assert.ok(schedule.length > 0);
  assert.doesNotMatch(schedule, /'Codex task scheduled'/);
  assert.match(schedule, /Clear-SchedulerAlert/);
  assert.doesNotMatch(schedule, /Update-Status "Scheduled once for/);
  assert.match(schedule, /'Unrestricted access'/);
  assert.match(schedule, /'Existing scheduled work'/);
  assert.match(schedule, /'Scheduling check failed'/);
});

test('pending list shows recognizable project and preserves full task identity', () => {
  const fn = namedFunction('Apply-PendingList');
  assert.match(fn, /\$project=if\(\$path/);
  assert.match(fn, /\$row\.Tag=\[string\]\$item\.Name/);
  assert.match(fn, /\$row\.Cells\[4\]\.ToolTipText/);
  assert.match(fn, /\$pending\.Text="Upcoming runs \(/);
  assert.match(source, /Add-Button 'Recent runs'/);
  assert.doesNotMatch(fn, /\$recent\b|\$resultIndex\b/);
  assert.match(fn, /\$script:ui\.Dashboard\.historySnapshot=@\(\$Items/);
  assert.match(fn, /\$script:ui\.Dashboard\.pendingSnapshot=\$upcoming/);
  assert.doesNotMatch(fn, /displayedRunCount/);
  assert.match(fn, /\$same=\(\$grid\.Rows\.Count/);
  assert.doesNotMatch(source, /\$removeResult\b|\$viewResult\b/);
  assert.match(source, /\$recentResults\.Add_Click/);
  assert.doesNotMatch(source, /\$grid\.Add_CellDoubleClick/);
  assert.match(fn, /\$emptyRuns\.Visible=\$false/);
  assert.match(fn, /Update-DashboardLayout/);
  assert.doesNotMatch(fn, /Update-Status/);
  assert.match(source, /\$cancelRun\.Enabled = \$false/);
});

test('background result does not override an entered root and list refresh retains it', () => {
  const lookup = namedFunction('Apply-SelectionResult');
  assert.match(lookup, /if \(-not \[string\]::IsNullOrWhiteSpace\(\$repoBox\.Text\)\) \{ return \}/);
  const sessions = namedFunction('Apply-SessionList');
  assert.match(sessions, /if \(\$selectedId -and \$chosen -and -not \[string\]::IsNullOrWhiteSpace\(\$repoBox\.Text\)\)/);
});

test('usage reports remaining and keeps reset as an explicit action', () => {
  assert.match(source, /Usage remaining/);
  assert.match(source, /% remaining' -f \$remaining/);
  assert.match(source, /\$useReset\.Add_Click\(/);
  assert.match(source, /\$card\.Reset\.Text = 'Usage unavailable; retrying automatically'/);
  assert.doesNotMatch(source, /\$card\.Updated|\$usageNotice|Next reset is informational/);
  assert.doesNotMatch(source,/\$refreshUsage|\$refreshSessions|\$refreshRuns/);
  assert.doesNotMatch(source,/Add-Button 'Refresh now'|Add-Button 'Refresh runs'/);
});

test('one coordinator handles timer and window-activation refreshes', () => {
  const lifecycle=fs.readFileSync(path.resolve(__dirname,'..','legacy/winforms/CodexUiLifecycle.ps1'),'utf8');
  assert.match(source,/function Request-SystemRefresh \{/);
  assert.match(source,/lastFullRefresh=Get-Date/);
  assert.match(source,/Refresh-SessionList/);
  assert.match(source,/Refresh-PendingList/);
  assert.match(source,/Request-UsageRefresh/);
  assert.match(lifecycle,/\$systemRefreshTimer\.Interval = 2000/);
  assert.match(lifecycle,/Request-SystemRefresh -Scope \$scope/);
  assert.match(lifecycle,/\$form\.Add_Activated/);
  assert.doesNotMatch(lifecycle,/\$autoRefresh|\$runStatusRefresh/);
});

test('dashboard shares the pending snapshot and renders distinct countdown and quota bars', () => {
  const dash = fs.readFileSync(path.resolve(__dirname, '..', 'legacy/winforms/CodexDashboard.ps1'), 'utf8');
  assert.match(source, /Columns\.Add\('Countdown','Time to run'\)/);
  assert.match(source, /\$grid\.RowTemplate\.Height = 40/);
  assert.match(source, /\$script:ui\.Usage\.usageRequestedModel = \$chosen/);
  assert.match(source, /compactMode = \[bool\]\$script:ui\.Dashboard\.compactToggle\.Checked/);
  assert.match(dash, /Get-RunCountdownPercent/);
  assert.match(dash, /\$grid\.Add_CellPainting/);
  assert.match(dash, /Set-AeroProgress \$script:ui\.Dashboard\.compactRunTrack \$percent/);
  assert.match(dash, /New-AeroProgressBar \$script:ui\.Dashboard\.compactRunPanel/);
  assert.match(dash, /Sync-DashboardRunBars/);
  assert.match(dash, /\$script:ui\.Dashboard\.compactRunHeading\.Visible = \$compact -and \$script:ui\.Dashboard\.pendingSnapshot\.Count -gt 0/);
  assert.match(dash, /\$form\.ClientSize/);
  assert.match(source, /New-AeroProgressBar \$card 12 44 400 17 \$Kind/);
  assert.match(source, /New-UsageCard 18 'Primary window' 'quota'/);
  assert.match(source, /New-UsageCard 470 'Secondary window' 'weekly'/);
  assert.match(dash, /Set-AeroWorking \$bar/);
  assert.match(dash, /Set-AeroWorking \$script:ui\.Dashboard\.compactRunTrack/);
  assert.match(dash, /\$barX=\$cell\.X\+6\+\$labelWidth\+6/);
  assert.match(dash, /function Get-RunLabelWidth/);
  assert.match(dash, /function Get-UpcomingGridHeight/);
  assert.match(dash, /\$actionTop=\$grid\.Bottom\+13/);
  assert.doesNotMatch(dash, /activitySpinner|activityTimer/);
  assert.match(source, /Set-AeroProgress \$Card.Bar \$remaining/);
  assert.match(dash, /New-AeroProgressBar \$grid 0 0 100 15 'time'/);
  assert.doesNotMatch(dash, /Draw-SchedulerProgress/);
});

test('routine status clutter is absent but actionable errors remain visible', () => {
  const dash = fs.readFileSync(path.resolve(__dirname,'..','legacy/winforms/CodexDashboard.ps1'),'utf8');
  assert.doesNotMatch(dash,/activityPanel|activityLabel|Update-DashboardActivity/);
  assert.doesNotMatch(source,/\$usageNotice|\$autoResumeCheck/);
  assert.match(source,/\$status = Add-Label ''/);
  assert.match(source,/function Update-Status \{/);
  assert.match(source,/\[switch\]\$Alert/);
  assert.match(dash,/\$status\.Visible\s*=\s*-not\s+\[string\]::IsNullOrWhiteSpace\(/);
  assert.match(source,/Clear-SchedulerAlert/);
});

test('compact switch occupies dedicated header space in both layouts', () => {
  const dash = fs.readFileSync(path.resolve(__dirname, '..', 'legacy/winforms/CodexDashboard.ps1'), 'utf8');
  assert.match(dash, /\$script:ui\.Dashboard\.compactToggle\.Appearance = \[System\.Windows\.Forms\.Appearance\]::Button/);
  assert.match(dash, /\$script:ui\.Dashboard\.compactToggle\.Text = 'Compact mode: OFF'/);
  assert.match(dash, /\$script:ui\.Dashboard\.compactToggle\.Text = 'Compact mode: ON'/);
  assert.match(dash, /\$script:ui\.Dashboard\.compactToggle\.Location = \[System\.Drawing\.Point\]::new\(298,13\)/);
  assert.doesNotMatch(dash, /\$subtitle\.Visible/);
  assert.match(dash, /\$heading\.Width = 270/);
});

test('pixel-art control groups and associated actions ship in the production app',()=>{
 const theme=fs.readFileSync(path.resolve(__dirname,'..','legacy/winforms/CodexUiPixelTheme.ps1'),'utf8');
 const lifecycle=fs.readFileSync(path.resolve(__dirname,'..','legacy/winforms/CodexUiLifecycle.ps1'),'utf8');
 const pack=fs.readFileSync(path.resolve(__dirname,'..','scripts/Package-CodexScheduler.ps1'),'utf8');
 for(const functionName of ['Set-PixelSurfaceStyle','Add-PixelBackplate','Set-PixelAction','Initialize-SchedulerPixelTheme']){
   assert.ok(theme.includes('function '+functionName),functionName+' missing');
 }
 for(const name of ['Conversation','Repository','RunTime','Options','Instruction']){
   assert.ok(theme.includes("Name='"+name+"'"),'Missing '+name+' grouped backplate');
 }
 assert.ok(source.includes('Initialize-SchedulerPixelTheme -Form $form'));
 assert.ok(lifecycle.includes('Set-PixelSurfaceStyle -Panel $script:ui.Dashboard.compactRunPanel'));
 assert.ok(lifecycle.includes('Set-PixelAction -Button $script:ui.Dashboard.appearanceButton'));
 assert.ok(pack.includes("'legacy/winforms/CodexUiPixelTheme.ps1'"));
});

test('secondary actions use a restrained blue palette with no violet and clear disabled states',()=>{
 const theme=fs.readFileSync(path.resolve(__dirname,'..','legacy/winforms/CodexUiPixelTheme.ps1'),'utf8');
 const lifecycle=fs.readFileSync(path.resolve(__dirname,'..','legacy/winforms/CodexUiLifecycle.ps1'),'utf8');
 assert.doesNotMatch(theme,/#785AC5|#F1ECFF/i,'Violet UI accents were retained');
 assert.match(theme,/Now='#516F98';Reset='#516F98'/);
 assert.match(theme,/Schedule='#2277A1'/);
 assert.match(theme,/Name='RunTime';Y=148;Height=44;Fill='#EDF3FA';Accent='#516F98'/);
 assert.match(lifecycle,/appearanceButton -Accent '#516F98'/);
 assert.match(theme,/\$Button\.Add_EnabledChanged\(\$updateState\)/);
 assert.match(theme,/\$disabledFill=\[System\.Drawing\.ColorTranslator\]::FromHtml\('#DDE4EE'\)/);
 assert.match(theme,/Primary:\(\$key -eq 'Schedule'\)/);
 assert.match(theme,/MouseOverBackColor=\[System\.Windows\.Forms\.ControlPaint\]::Dark\(\$color,\[float\]\.10\)/);
});
