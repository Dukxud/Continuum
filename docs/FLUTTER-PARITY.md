# Flutter parity acceptance — Windows v1.16 baseline

The accepted main-branch WinForms Scheduler v1.16.0 is the source of truth.
This Flutter candidate is an alternate UI, not a new scheduler engine.
The Windows bridge invokes the existing verification, pinned-runtime,
Task Scheduler, history and worker functions; this is not a backend rewrite.

## Requirements and evidence

| V1.16 behavior | Flutter implementation | Acceptance |
| --- | --- | --- |
| CLI conversations, model/effort/access | Live bridge to original data/Codex catalog | Windows manual pending |
| Repository discovery, alternatives and explicit Browse | Bridge resolution + conflict UI | Windows manual pending |
| Manual time, minus/plus, Now+2, reset+2 | Flutter controls, server checks before scheduling | Windows manual pending |
| Live model-specific 5-hour/weekly usage | Official CodexUsage.js, no estimated quota | Windows manual pending |
| Full run form and compact next-run view | Flutter, separate desktop window sizing | Window test added; Windows visual pending |
| No upcoming-run message in compact mode | Hide next-run area when no task | Widget covered |
| Distinct countdown progress / running state | Native renderer with original working mode | Visual pending |
| Approved Windows v1.8 pixels and v3 Aero Liquid optical GLSL | Exact source PNGs; mechanically adapted original fragment shader | Source byte/hash checked; GPU visual pending |
| Rounded partial droplet; square full tip | Original GLSL cap contract retained | Visual pending |
| Independent 5-hour / weekly / countdown / working colors | Same v1.16 barAppearance schema | Unit tested; visual pending |
| Custom RGB, glass/enamel/pearl, studio modes, shimmer, speed, toggle | Full transactional appearance editor, live preview/Cancel/Defaults/Save | Unit/widget coverage; Windows visual pending |
| Pinned runtime and one-time task registration | Existing PowerShell RuntimeBundle + OneTimeTasks | Source checked; real task pending |
| Workspace identity, model/effort, quota, branch and overlap checks | Existing worker plus server-side registration preflight | Real task pending |
| Cancellation before worker starts, never cancels running process | Original OneTimeTasks with post-cancel reconciliation | Real task pending |
| Upcoming and recently completed/legacy Windows results | Task Scheduler + saved JobOutcomes | Windows manual pending |
| Detailed history: result, time, exit code, attempt, next task, message | Flutter history dialog, response and worker transcript | Windows manual pending |
| Copy response / copy worker log / remove from history (non-destructive) | Flutter dialog / bridge | Windows manual pending |
| Autosaved draft without preview leakage | Same schema; preview freeze during appearance dialog | Source and unit checks; Windows manual pending |
| No terminal after launch | Native Flutter Windows executable in local unsigned preview bundle | Windows manual pending |
| Mac, Linux and web execution | Not implemented: independent platform adapters needed | Out of Windows-port scope |

## Conditions for acceptance

1. Run a single bounded source-integrity, Dart analyzer and widget/unit-test pass with Run-WindowsReview.ps1 on BLACK-PUDDLE. Stop on any failure; no automatic retries or unbounded CI.
2. Compare full and compact Flutter windows directly to accepted v1.16. Verify actual window resize, original optical reflections, each appearance control, color customizations, reset, and transactionality.
3. Schedule **one safe read-only** test run in a disposable Git repository and a verified CLI session. Read the actual worker result and evidence; Task Scheduler exit 0 alone is insufficient.
4. Schedule and cancel a separate future run. Verify the Windows task is unregistered, the cancelled outcome is visible, and no worker was started.
5. Inspect model/effort, workspace verification and quota fail-closed behavior, conflicting repository hints, near-past times, and user-preserved settings.
6. Independently review the changed bridge/UI for safety, clean code, no duplicate worker rules and reliable process exit handling.
7. **Do not merge or publish** until these gates pass on the actual Windows machine. The WinForms v1.16 app remains authoritative and usable.

## Windows commands

From a checkout of feat/flutter-windows-review-v0:

    pwsh -NoProfile -STA -File .\flutter_port\Run-WindowsReview.ps1

After acceptance, create a standalone unsigned local archive (never publish it):

    pwsh -NoProfile -STA -File .\flutter_port\Build-WindowsPreview.ps1

The release archive bundles the Flutter executable and the original worker;
it does not change Task Scheduler jobs created by the existing GUI. It is
**unsigned**, requires existing PowerShell 7, Node, Git and npm Codex, and
makes no antivirus-exclusion or signing-bypass changes.

The Flutter interface and original fragment program are portable assets.
The only current scheduler adapter is Windows. A macOS, Linux or web product
requires explicit platform worker/scheduler adapters and independent acceptance.
