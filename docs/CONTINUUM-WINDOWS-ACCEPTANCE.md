# Continuum Windows acceptance gate (current)

**Applies to:** Flutter GUI and all three execution modes on merged `main`. Unlike [the v1.16 WinForms checklist](WINDOWS-ACCEPTANCE.md), this is **not** a PR #16 blocker or a requirement to merge already merged PR #17/#18. It is a gate for **declaring the current Flutter feature accepted** and for any **future public production release**.

**Status at 6 Nov 2026:** GitHub Windows mock/source/widget/packaging CI succeeded on shared-feature commit `6cd11c6f2f59159addeb900fcf61ba38cadeafe4` (run [42249396861](https://github.com/Dukxud/codex-resume-scheduler/actions/runs/42249396861)); its tree matched merged `main` commit `15b32f74b0ea243e1e0bfa833ff33aa073c59089`. On BLACK-PUDDLE, **BP207** reported that this preview launched. The first live attachment task (prior build) finished successfully but its TUI disconnected on scheduled-turn completion; this exposed a lifecycle defect. The code fix is present in `main`, but **a repeat real native TUI test and cross-surface question/approval acceptance have not been provided**. Do not mark those cells passed without evidence.

## Evidence levels

| Level | What it proves | Current evidence |
| --- | --- | --- |
| 1 — static/mock | Source checks, bridge/mock protocol, Flutter tests, no live Codex | Windows CI passed on pinned shared-feature SHA |
| 2 — native package | Unsigned Windows package built and app launched on target device | BP207 preview launch PASS |
| 3 — scheduled execution | Saved task actually runs original thread and records the correct outcome | Initial 90-second disposable shared turn completed; pre-fix TUI lifecycle failed |
| 4 — retained native attachment | Native TUI stays connected after turn; owner shuts down safely when viewer exits | **Not yet verified on fixed code** |
| 5 — dual-surface approvals/questions | One owner; requests answered correctly via GUI/TUI, no duplicate writer | **Not yet verified** |
| 6 — public distribution | Signed installer/release, security/AV review, onboarding and support | **Not complete** |

## Preflight (safe, does not run Codex turns)

- [ ] Confirm `git rev-parse HEAD` matches the reviewed checkout/preview manifest; no mixed artifacts.
- [ ] Windows PowerShell 7, Node, Git, npm Codex, Flutter runtime payload and pinned worker modules available. Check normal, compact/Monitor and Micro windows.
- [ ] Inspect full/Monitor/Micro layout at 100% and 125% scaling; no clipped fields, correct clickable time edit, date/time button alignment, scroll/tab behavior, Always on Top, close/reopen persistence.
- [ ] Preview builds, immutable worker integrity and SHA-256 package manifest checks pass.
- [ ] Run each test **once**; no infinite CI loop. For tests that only use mocks, do not start a Codex CLI turn.
- [ ] Verify app window appearance, bars, custom colors and motion with actual on-device screenshots; distinguish a screenshot from a synthetic widget rendering.

## Scheduling and results

- [ ] Select a disposable saved conversation; repository Git root and branch match intended checkout or require explicit override.
- [ ] Confirm model/effort catalog is dynamically loaded; ambiguous quota/account mapping disables unsafe scheduling.
- [ ] Date/time manual entry, increments, Now, Reset, and Monday-first calendar behave correctly. Reject past/ambiguous times.
- [ ] Read-only and workspace-write reflect intended policy; YOLO requires explicit confirmation.
- [ ] Scheduled tasks are unique; overlapping scheduler-owned runs on the same conversation do not create two writers.
- [ ] Upcoming task has stable status; recent results preserve `completed`, `finished`, `failed`, `blocked`, `deferred`, `cancelled` without inventing a success.
- [ ] Cancellation only claims to remove a not-yet-started run; running worker termination is not implied.
- [ ] Existing pinned workers and older jobs remain untouched by a GUI upgrade.

## Execution modes (live Codex only with owner authorization)

### Background
- [ ] Resume the same conversation in verified checkout without a TUI; preserve and read structured result.
- [ ] Auto-resume is off by default, cannot activate on old payloads, requires a verified exhausted-window reset, and schedules at most three follow-ups; generic errors do not retry.
- [ ] No duplicate job or hidden indefinite retry loop.

### Native terminal
- [ ] Interactive Codex TUI opens using the saved conversation and configured model/access; prompt is visible.
- [ ] Questions and approvals function directly in terminal.
- [ ] Closing terminal yields `finished` rather than claiming the requested work completed.
- [ ] No multiple writers.

### Shared session
- [ ] Exactly one App Server owner; Continuum status/requests track that owner's thread and active turn.
- [ ] While the turn is running, **Open Codex Terminal** launches the real remote TUI as a **viewer**, not a new conversation/turn.
- [ ] TUI shows the **same** conversation; no unintended fork and no extra execution owner.
- [ ] On turn completion, app reports `completed`. **Leave attached TUI open for at least 30 seconds**; confirm **no reconnect loop** and owner remains alive.
- [ ] Exit TUI; owner shuts down after bounded idle grace; descriptor is cleaned up; `*.result.json` reports the real outcome. Flutter must not display stale `Codex: running` or a misleading "not accessible" error after normal cleanup.
- [ ] Test native TUI attachment attempted after owner completed but during idle grace, and refusal after owner lifetime expired.
- [ ] With a live approval/question, verify **one** resolution via chosen surface, explicit decision, no accidental double-accept, no cross-thread/cross-turn request.
- [ ] Simulate disconnected/abandoned terminal and enforce two-hour maximum lifetime, without hanging process cleanup.

## Screenshot and evidence requirements

Follow [SCREENSHOTS.md](SCREENSHOTS.md). Provide at least a **Full window**, **Monitor/Micro**, **Appearance Colors/Optics**, **Shared live panel**, **native attached terminal**, and **post-completion Shared status**. Crop unrelated windows, redact user/profile names, session UUIDs, paths, repository contents, tokens and activity transcripts. Preserve build/commit identification separately in the caption.

## Closeout

No release or acceptance claim should be made without the appropriate native proof. PR merges #17/#18 are historical facts; they **do not** retroactively satisfy every manual test. Save failed observations as defects and write regression tests around the *actual behavior*. A new live Codex run must be explicitly authorized by the operator.