# Contributing and restart discipline

**Project paused by the owner.** Start with [CURRENT-STATE.md](CURRENT-STATE.md); do not continue feature work, run model turns, merge another PR or publish automatically. `main` is authoritative, including the accepted icon and quota correction.

## Scope and ownership

Keep changes narrow and reviewable. Flutter owns presentation/windowing; the JSON bridge and pinned worker own Windows scheduling/authorization/outcomes. Shared has one execution owner with authenticated clients; do not introduce a second writer. Plus/Pro labels come from returned window data, not guesses about tier or array position. Keep generic components separate from application orchestration. Do not erase historical evidence or represent a merge as a native pass.

## Verification when work is authorized again

From a complete checkout in PowerShell 7:

```powershell
node --test tests/shared-codex-session.test.mjs tests/shared-codex-remote.test.mjs
if($LASTEXITCODE -ne 0){throw 'Shared mock tests failed'}
pwsh -NoProfile -STA -File .\flutter_port\Run-WindowsReview.ps1 -TestsOnly
if($LASTEXITCODE -ne 0){throw 'Windows/Flutter checks failed'}
```

The review script runs source/bridge checks, runner generation with pinned icon, dependencies, analysis and tests once. The package builder adds release compilation and integrity verification. Never turn a failing gate into an unbounded retry/poll loop. Inspect actual failed evidence, fix its cause and record a bounded retest.

Node mocks and in-memory Flutter quota fixtures do not launch live Codex turns. Actual account/CLI interactions require explicit operator authorization. Do not replay private work, schedule jobs, or enable YOLO as incidental verification. On-device acceptance is a separate [checklist](CONTINUUM-WINDOWS-ACCEPTANCE.md).

## Delivery and documentation

Every reviewable Windows build must include the exact artifact/run/SHA, a copy-paste download/open command, the full executable path and what that command will execute. Preserve previous preview folders. Do not clone new source then call an old EXE a new build. Provide expected observations and distinguish missing evidence from failures.

Update current state, affected contracts and QA evidence with each accepted change; historical reviews remain labeled as historical. Screenshots must be real, privacy-reviewed and captioned by build/outcome. The optional [capture helper](../scripts/Capture-ContinuumScreenshot.ps1) saves private local files and is not automatically run/uploaded. Its native capture behavior still needs operator validation.

Open issues with sanitized reproducible evidence, not tokens, raw session IDs or private transcripts. No merge without explicit authorization; no publication as a side effect of cleanup.
