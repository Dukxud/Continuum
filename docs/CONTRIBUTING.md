# Contributing to Continuum

## Project status

`main` is the merged Flutter Continuum baseline (PR #17 foundation, PR #18 Shared native TUI). The historical WinForms implementation and its independently reusable PowerShell modules remain in the repository; the old [v1.11 release](https://github.com/Dukxud/codex-resume-scheduler/releases/latest) is **not** the current Flutter binary.

Work on an isolated branch with a narrow PR. **Never merge without the maintainer's explicit authorization.** Do not publish a release or change code-signing expectations as part of a documentation/feature PR.

## Development safety

- Source formatting, Node mock protocol tests, PowerShell syntax/bridge tests, Flutter analysis/widget tests and Windows **builds** are permitted by the standard development gate.
- Do **not** invoke live Codex turns or approvals as an automatic test. A test requiring actual Codex must state the task, expected cost/permissions, and ask the operator to authorize it.
- Do not replay a real saved conversation, grant YOLO, or alter an existing Windows Task Scheduler task just to make tests green.
- No infinite CI loop. Bound test retries and report failure IDs. Native acceptance on BLACK-PUDDLE precedes certification of actual Windows behavior.

## Local checks (PowerShell 7, checkout on Windows)

```powershell
node --test tests/shared-codex-session.test.mjs tests/shared-codex-remote.test.mjs
pwsh -NoProfile -File .\tests\flutter-port-source.test.ps1
pwsh -NoProfile -STA -File .\tests\flutter-port-bridge.test.ps1
pwsh -NoProfile -STA -File .\flutter_port\Run-WindowsReview.ps1 -TestsOnly
```

For full reproducible source-level validation of legacy WinForms modules, consult [historical Windows acceptance](WINDOWS-ACCEPTANCE.md); it is **not** a substitute for current Flutter-native acceptance.

## Architecture constraints

- Flutter owns presentation/windowing; Windows PowerShell bridge validates inputs and orchestrates Windows Task Scheduler.
- Pinned PowerShell worker owns unattended execution and durable outcomes; no GUI-owned timer replaces Windows Task Scheduler.
- Shared mode owns **one** App Server; TUI windows are authenticated viewers, never an independent writer. Pre-turn approvals, permission escalation and cross-thread requests must fail closed.
- Keep modules small, separable and meaningful. Do not introduce duplicated workers, globals or magic retries.
- Keep code-level claims aligned with implementation; distinguish **build/mocks** from **real Codex Windows acceptance**.

## Docs and screenshot contribution

Document exact tested commit, required OS/CLI version, access, expected vs observed behavior, and a non-sensitive screenshot. Use the [screenshot guide](SCREENSHOTS.md) and [capture script](../scripts/Capture-ContinuumScreenshot.ps1). Screenshots **must be reviewed/redacted before uploading**; they often contain session IDs, file paths, usage percentages, private prompts or secrets. Never advertise a historical pre-fix capture as current passing behavior.

## Submit feedback

Use [Issues](https://github.com/Dukxud/codex-resume-scheduler/issues) with reproducible steps, a pinned SHA, source vs package distinction, and sanitized evidence. Include no user secrets or raw terminal session files.