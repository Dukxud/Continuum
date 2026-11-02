# Adversarial source review — v1.16 development branch

## Scope and verification

This pass examined the current GUI entrypoint, worker, data readers, scheduling and cancellation paths, repository lookup, quota/model controllers, renderer adapters, and all ten reusable module implementations and export manifests.

No CI tests were used or checked during this pass. The review used source inspection and dependency/contract consistency checks only. No Windows PowerShell, Task Scheduler, WebView2 rendering, real Codex account, or antivirus execution was performed.

## Corrected defects

1. Browse previously wrote an obsolete Selection.dataQueued property. It now invalidates the queue owned by Async.dataQueued.
2. Direct WPF bars created without WebView2 were never registered for live appearance changes. They are now tracked, recolored in place, and removed with their owner.
3. The generic FlowingProgress module previously commandeered ElementHost.Tag. Its percentage is now held in module-owned weak-key state; other programs can use Tag independently.
4. Native WPF material updates now target a named FlowFill template element rather than relying on a positional visual-tree index.
5. CodexData repository and pending-task readers no longer depend on an ambient appDir global. The async dispatcher passes AppDirectory explicitly. Session-ID validation is local to its reader.
6. An error saving a draft or refreshing the interface after validated task registration no longer reports scheduling as failed. Cancellation refreshes the list even when subsequent cleanup fails.
7. A broken hexadecimal color validator introduced during source editing was identified and corrected before completion.

## Architectural judgment

All ten module implementations were inspected for Codex and UI-state imports, and their function exports were compared with their definitions and manifests. No such dependency or export discrepancy was found. The scheduled worker dispatches before UI initialization and does not load application UI modules.

The application-specific WinForms controllers still coordinate through shared application-owned controls and state. They are intentionally not offered as reusable library modules. The general-purpose components are independently importable within PowerShell; visual and scheduled-task components remain Windows-specific.

## Residual risk and acceptance boundary

- Native WPF live recoloring and its module-owned state have not been executed on Windows in this pass.
- Actual Task Scheduler registration, retry scheduling, failure propagation, account switching, and WebView2 process recovery have not been observed on the target computer.
- The backend can omit or conflict on workspace identity. Auto-resume must fail closed rather than guess.
- The preview remains unsigned. Actual antivirus behavior and production signing need separate verification.
- SHA-256 worker snapshots detect accidental drift, but do not authenticate against a same-user attacker able to change both job metadata and files.
- Older pinned-runtime folders are not automatically garbage-collected. Safe cleanup requires proof that no registered task still refers to them.

**Disposition:** Keep PR #16 in draft. The source-level correction is complete; runtime and distribution acceptance are not established without Windows execution. This review intentionally did not use CI.

## Final bounded adoption corrections (source-only)

1. The generic AeroProgress module no longer claims Control.Tag. A status snapshot API now owns Ready, Failure, Color and requested Value, and its initialization/navigation error paths report errors without assuming that an exception message exists.
2. CodexAeroBar owns only its own quota/time Tag data and uses the generic status API to detect real WebView2 failures, retaining its existing WPF recovery mechanism.
3. The standalone consumer source asserts that updating AeroProgress does not overwrite arbitrary host metadata. Existing integration sources now query the public status API. These cases were reviewed, not executed.
4. SettingsStore is expressly limited to replaceable preferences, never the adopting application's durable measurements.
5. The main workflow is manual-only; PR #16 removes the release job and targets main directly. Earlier PRs #14 and #15 are marked superseded. Preview packaging is still available.
6. A direct Windows acceptance checklist and an explicit release policy were added to the repository. The merge remains blocked until actual target-device evidence establishes functionality and security.

No CI was run or inspected during this closeout. The newest changes have not been operationally verified, and PR #16 is intentionally left as an unmerged draft.

## Local Windows acceptance finding — 2026-11-01

On BLACK-PUDDLE, the pinned v1.16 candidate passed 35 of 36 local test files. The integrated two-bar Aero WebView2 rendering test failed **before navigation** with HRESULT 0x8007139F on both bars (CoreWebView2 remained null). The independent packaged Aero renderer succeeded with a unique user-data folder. Microsoft documents ERROR_INVALID_STATE when WebView2 environment options conflict with an existing browser process sharing a profile. This is evidence of a possible shared-profile conflict, not proof.

The integrated renderer test now supplies a unique per-run user-data directory explicitly to both bars. This isolates the test from installed application profile state without changing production's default profile. A targeted local rerun must establish whether the failure is profile-specific; if the default production profile remains unusable, this source-only correction is insufficient. No CI tests were run.

## BLACK-PUDDLE production-task forensics, 2026-11-01

The task-scheduler service was running and Task Scheduler launched all three newest one-time jobs. One attempt at 19:52 failed with an exhausted usage limit. The 20:57 attempt ran to 21:40 with Codex exit code 0 and performed actual Horizon work. The 21:10 attempt failed because the same Codex conversation already had an active thread-store writer: the 20:57 turn was still running.

All three saved payloads had autoResume=false. Therefore the first usage-limit failure was not eligible for automatic retry. The installed GUI showed v1.14 and tasks used pinned v1.14-era runtime assets, whereas the development candidate is v1.16. No result JSON files were found for those older jobs; their older runtime behavior is not evidence that the v1.16 outcome writer failed. The single-use tasks remained registered after their past triggers. Do not assume a "Due now" countdown proves a running process.

This exposed a safety gap: new one-time tasks were allowed to compete for the same session. The v1.16 worker now takes a nonblocking cross-process Windows named mutex per Codex session, holds it through the CLI command, and writes a blocked result instead of launching a second overlapping scheduled continuation. If a manually launched Codex process owns the writer, the worker recognizes the native thread-store conflict and records blocked without retrying. Abandoned mutex ownership fails closed for that attempt.

A separate local worker integration fixture now includes a parent-held mutex and a child worker, and a mock native-writer conflict. They must be run on BLACK-PUDDLE at the new exact commit; no CI tests were run. Old pinned scheduled workers cannot gain this guard retroactively. Existing Horizon jobs, their branches, and old Task Scheduler registrations were deliberately not changed.

## BLACK-PUDDLE complete-suite feedback, 2026-11-02

The exact earlier candidate `a53ab0a` ran 35 discovered test files: 34 passed, 1 failed (`dashboard-visuals.test.ps1`, assertion comparing one animated time-fill pixel with the unfilled track). The prior WebView2 profile-isolation failure was resolved; the live WebGL2 rendering test passed.

During the automated appearance-dialog test, Windows Forms displayed an unhandled callback exception stating that draft changes persisted too soon, although the test process returned PASS. Source investigation revealed the test registered a second timer event handler without removing the first; that first handler attempted a save during the subsequent Cancel phase. This is a **false-green acceptance test defect**. The test now has a single nonreentrant timer handler and captures event exceptions as actual test failures. The application save path also persists the pre-dialog appearance while live preview is open, preventing any outstanding settings-autosave from persisting an unaccepted draft.

The WPF color assertion remains strict until further evidence. The visual test now prints measured fill/track RGB values across several positions before its assertions. The new snapshot **has not yet been executed locally**, so pixel evidence must determine whether the fill is genuinely wrong or a transient animated-sample problem. The review does not call that failure resolved.

Execution visibility was also deficient: the compact dashboard displayed `Due now` even after a one-time job had launched, completed, or failed, encouraging the owner to schedule duplicates. The data reader now combines Windows task state, recent trigger and last-run information, and validated worker outcome files, explicitly distinguishing `Running`, `Scheduled`, `Completed`, `Failed`, `Blocked`, `Ended (no result recorded)`, and `Overdue (execution unconfirmed)`. The UI polls task state separately from slower usage polling and only offers Cancel for future tasks; it does not suggest unregistering a running job would kill its process. A new local-only status test uses mocked Task Scheduler objects. No CI was run.

## Cancellation is not process termination

The WinForms dashboard refreshes asynchronously, so its remembered row status can become stale while a task is about to fire. The generic OneTimeTasks removal API now offers a conservative `-OnlyBeforeStart` guard: it rereads Windows task state, requires one future trigger at least 90 seconds away, and refuses to label a task cancelled if the task has actually executed. The UI uses this guarded operation and does not write a cancellation result or delete the payload when the guard rejects. Plain removal remains available for explicit maintenance. This mitigates, but cannot mathematically eliminate, a race with an external Task Scheduler administrator; the guard avoids the common near-trigger window. Code has not yet been run on Windows in this pass.
