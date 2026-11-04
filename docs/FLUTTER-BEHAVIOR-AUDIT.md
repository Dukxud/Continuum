# Flutter ↔ WinForms v1.16 behavioral parity audit

**Baseline:** original WinForms `main`/v1.16 contracts. **Candidate:** PR #17 draft Flutter Windows port. The original PowerShell worker is unchanged. A test passing on a different commit does not certify the current candidate.

This is a requirements-to-implementation audit, not an assertion that native or security acceptance is complete. **Status legend:** E = equivalent by source review; F = discrepancy corrected in draft, exact-head CI/native recheck required; N = original worker reused (no new backend implementation); V = owner-verified on an earlier native build; O = open/device evidence required. User-approved changes to appearance interaction are intentional, not lost requirements.

## Contract traceability

| ID | WinForms source of truth and required behavior | Flutter implementation | Verdict / acceptance check |
|---|---|---|---|
| P01 | `CodexData.Get-RecentCliSessions`: only resumable `cli`/`exec` sessions, not IDE/subagent | Original reader via `windows_bridge load` | N. Recheck restored and fresh sessions on native device |
| P02 | `CodexUiSelection.Apply-SessionList` immediately requests `Find-SessionRepository` via `CodexData.Get-ReportedThreadDirectory` for the selected saved/first CLI conversation, unless preserving an explicitly selected root; repeat on later full refresh while unresolved | Flutter bridge already reused the exact WinForms resolution but Flutter controller called `select` **only after the user changed the dropdown**, not after startup restoration or regular refresh; it also failed to select the newest session when a saved ID disappeared | **F: CONFIRMED root-cause divergence.** Restore automatic coalesced lookup on startup/refresh, select first existing conversation if saved ID disappeared, clear stale associated root, protect user edits (including clear-to-empty) and ignore stale async lookup results. Add regressions and native acceptance |
| P03 | `CodexUiSelection`: one active model and supported non-Ultra efforts from live catalog | `readUsage`, `selectModel`, `efforts`, Windows preflight | E / tests; native catalog/effort changes still need exercise |
| P04 | Canonical workspace hash required at scheduling and worker start; never email-only | Original `CodexUsage.js`/worker, live verified hash preflight | N. Native account-switch/unknown-identity rejection remains O |
| P05 | `Update-SchedulingEligibility`: fresh (120s) model-matched quota/catalog and identity; unavailable/stale snapshot disables scheduling | `canSchedule` requires model, effort, fresh matching snapshot, verified hash | E by source review; negative tests must cover stale/invalid snapshot |
| P06 | Quota at 0% can still register a *future* run; execution-time worker independently rejects exhausted quota | Earlier Flutter controller+bridge blocked registration; both checks removed | F. Logic+widget regression added; native future-run check O |
| P07 | `CodexScheduleTime`: +2 minutes rounded up; + and − respect 30-second minimum; manual time preserved; Reset +2 uses verified reset only | Dart helpers and bridge wall-clock validator | E/source+unit; Windows DST and past-time boundary integration exists, native Reset +2 O |
| P08 | `CodexUiActions`: confirm YOLO and repository overlaps; block duplicate running conversation | Flutter dialogs plus original bridge validation | E; adversarial native overlap/YOLO O |
| P09 | `RuntimeBundle` + `OneTimeTasks`: one immutable pinned runtime and one Windows registration; no new retry | Original worker and Windows components, thin Flutter bridge | N; BP158 real read-only scheduled execution passed, exit 0 and persisted outcome |
| P10 | Registration is not success proof; worker validates repository, branch, model, quota, identity and records actual exit | Same original pinned worker | N; BP159 result and clean disposable repo passed |
| P11 | Cancellation refuses already running, too-near-to-start, or previously executed jobs; records cancelled | Direct one-click `cancelSelected`; original `Remove-OneTimeTask -OnlyBeforeStart` | E in source, earlier GUI disappearance reported; BP160 task/outcome verification O |
| P12 | Pending = Scheduled/Running only; no stale completed jobs; historical legacy outcomes separately | `SchedulerController.upcoming`, `Get-FlutterHistory`, list/grid/compact views | E. Running/completion transitions native O |
| P13 | Recent results show status, exit, attempt, nextJob, exact response and transcript; copy and non-destructive hide | Flutter dialog and original `Get-CodexRunEvidence`/history store | E/source; malformed/missing evidence and persistence native O |
| P14 | `CodexUiLifecycle`: focus return refreshes if stale (15s), 2-second task checks, 60-second full refresh, coalesced | Earlier Flutter omitted focus event; `onWindowFocus` + `refreshOnFocus` added | F, logic regression; native sleep/focus O |
| P15 | Startup refresh failure recovers on next successful read | Flutter previously stayed `ready=false` after failed initial load; later `load()` skipped initialization | F: `load(initial || !ready)` and focus recovery, regression added |
| P16 | `CodexUiLifecycle`: close persists draft regardless of debounce and surfaces failures | Flutter previously cancelled unsaved timer; now intercepts native close, awaits serialized flush, keeps window open on save failure | F, logic regression; Alt+F4 and immediate close on BLACK-PUDDLE O |
| P17 | Form edits persist session, repo, message, model, effort, access and time; editor changes user-approved as automatic | Same local `settings.json` and schema, serialized writes | E/V for appearance; native draft close/restart O |
| P18 | `CodexDashboard` full/compact layout, content-fit sizing, next job, no compact schedule form | Flutter fixed geometry and queued native window resizes | V: owner passed BP154 full/compact, tabs, autosave |
| P19 | `Countdown`: UTC-based elapsed time, days include hours **and minutes**; elapsed fraction rounded/clamped 0..100 | Dart earlier omitted day minutes and sent unbounded fractional elapsed percent | F: canonical helper/test, dynamically measured label width; native countdown O |
| P20 | Running displays `Running` and working-colored indeterminate bar; no fake percentage | Earlier compact ETA showed countdown even while Running; now shows Running | F, widget regression; native active worker O |
| P21 | Usage failures explicitly mark the *cards* unavailable, not just global footer | Earlier Flutter showed generic reset-unavailable when live read failed | F: in-card unavailable feedback and regression; native failure O |
| P22 | Approved original source pixels and liquid shader with rounded partial vs square full tip, independent colors | Original sprites/shader adapted and source-checksum tested | V on user's native visual inspection; explicit 100%/99% and screen-reader/GPU evidence O |
| P23 | Appearance presets/custom RGB, four independent colors, material, lighting, strength, speed, toggle | Two visible tabs and automatically persisted changes, user-approved intentional UX difference | V BP154; appearance-editor DPI/accessibility stress O |
| P24 | Windows-only signing/security contract; GUI cannot substitute arbitrary worker code from user checkout | Earlier adapter searched current working directory **before** bundled executable parents | F: packaged executable path now authoritative, test synthetic conflicting workdirs; native O |
| P25 | Native Windows task backend; Flutter UI portability does not imply cross-platform scheduling | Adapter requires Windows and PowerShell 7; no Linux/macOS scheduler | E. No cross-platform capability claims |
| P26 | Original v1.16 must remain available, and PR merge/release require authorization | Draft PR only; CI packages private unsigned preview | E; never merge/publish automatically |

## November 4 repository-discovery root cause

**WinForms vs Flutter source diff:** `CodexUiSelection.Apply-SessionList` invokes
`Request-SelectionLookup` whenever a selected conversation has no preserved
root; the asynchronous `CodexUiRefresh` reader obtains the Codex App Server
reported CWD and passes the selected session through `Find-SessionRepository`.
Flutter's `windows_bridge.ps1` already exposed these **same functions** under
`select`, but `SchedulerController.load` populated the selected session
from preferences without ever calling `select`. The only caller was the
dropdown's `onChanged`. Thus the bridge was functional (BP155 proved it),
but startup and refresh never requested discovery. When the saved session ID
vanished, Flutter also left `sessionId=null` instead of choosing the first
available session as WinForms does, and could retain that vanished session's
saved repository root.

**Corrected controller behavior:** automatically resolve a selected session
with no preserved repository on initial load and later full refresh, coalescing
duplicate in-flight requests. Preserve the saved root only when its saved
session still exists. Preserve explicit manual repository edits even if the
user clears the field while lookup is underway; reject stale responses from
earlier selections. Synchronize the displayed textbox after asynchronous
changes so an old root never remains visually attached to a new session.

**Honest limit:** the screenshot's selected `Nathan | 11/04 11:27` session
is **not** the previously tested `BP155-Flutter-QA` session. If the original
resolver receives no verifiable Git evidence for `Nathan`, both UIs must
leave its root unresolved; guessing the previous checkout would be a safety
regression. Final native acceptance must test both a known Git-backed CLI
conversation and the specific `Nathan` conversation separately.

## High-impact corrections in this pass

- **Scheduling:** Preserve ability to create a future run at 0% while preserving worker-time quota enforcement.
- **Lifecycle:** Recover failed first load; refresh on focus; flush unsaved draft before native close and refuse silent data loss.
- **Time and run display:** Exact WinForms countdown semantics; integer clamped elapsed fill; Running compact label.
- **Safety/UI:** Prefer bundled Windows worker over an unrelated launch directory; don't offer cancellation on already-running selected jobs; show failed quota reads inside usage cards.

These issues were established from both source paths, not inferred from screenshots. The newer `Nathan` session's unresolved repository is **not yet** established as a regression; validate its saved CWD and `thread/read` on BLACK-PUDDLE.

## Adversarial acceptance specification

| Test | Setup | Required outcome |
|---|---|---|
| A01 | Stub/model catalog with exhausted current quota, verified account | Future Schedule enabled; bridge can register; worker still blocks if quota remains exhausted at execution |
| A02 | Fail first `load`, then restore network/bridge | Next refresh or focus recovers `ready`, selected conversation and draft; no restart required |
| A03 | Edit instruction/repo/time, immediately close using X and Alt+F4 | Saved values survive restart; failed save keeps window open with actionable error |
| A04 | Focus after 16s vs 2s away | One full refresh only if stale; ordinary 2s task/status checks still work |
| A05 | Change session during slow repo lookup or use Browse | Stale lookup never overrides newer selection or manual repo; different CLI thread without Git evidence remains unresolved |
| A06 | Countdown beyond one day and across DST; invalid/old CreatedAt | Days/hours/minutes displayed; UTC math; fill 0..100 integer or unknown |
| A07 | Running task while Flutter shows full and compact | Running label and working bar; Cancel unavailable; no fake progress percentage |
| A08 | Force quota read failure / mismatched model / unknown workspace | Cards show unavailable; Schedule disabled until fresh, matching, verified identity returns |
| A09 | Launch from another directory containing fake bridge and worker filenames | Packaged worker chosen; no substitution from launch directory |
| A10 | Run safe read-only isolated continuation on actual Task Scheduler | Correct session, branch, access, response; persisted completed result and unchanged Git fixture |
| A11 | Cancel future isolated run | Task removed from Windows, cancelled outcome, no worker start/log; never cancel an active process |
| A12 | Native history, appearance, screen readers, 100%/125% DPI and Aero 99/100% | No clipped controls/AXTree crash, correct evidence/copy/hide, rendering matches approved baseline |

## Review and release gates

1. **Static review:** scrutinize cross-boundary payloads, async races, fail-closed behavior, no code copied from the worker into Flutter, and no god-files or compatibility machinery.
2. **Exact-head CI:** run the bounded Windows Flutter workflow and record commit, analyzer, tests, source asset/hash checks, native debug/release compilation, package manifest. A green previous commit does not count.
3. **Independent adversarial review:** required before merge; this author/source audit is not independent.
4. **BLACK-PUDDLE:** targeted A02–A05, A07–A12 against the **same** verified final artifact. Prior BP154/158/159 evidence remains historical, not a substitute for validating altered paths.
5. **Authorization:** draft PR #17 remains unmerged; any merge and signed/public release require explicit owner approval.
