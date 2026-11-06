# Troubleshooting Continuum (Windows)

These checks are **read-only** unless explicitly stated. Run in PowerShell 7 on the same Windows account that scheduled the job. Replace the example paths if your checkout differs.

## First check: Which application am I running?

The **Flutter** executable is named `codex_resume_flutter.exe`. A locally built preview from the documented command resides at:

```text
%USERPROFILE%\Downloads\Continuum-Main\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe
```

The older v1.11 public release launches a **WinForms** window through `Start-Codex-Scheduler.vbs`; it is not the Flutter build. The Flutter executable **requires the other files in its package directory**. Starting a lone copied EXE can fail.

### Verify the source baseline (no Codex run)

```powershell
git -C "$HOME\source\continuum" log -1 --format="%H %s"
```

Confirm `main` is at the commit you intend to review. The first merged Continuum baseline was `15b32f74b0ea243e1e0bfa833ff33aa073c59089`.

## "No model", "usage unavailable" or disabled scheduling

1. Confirm Node, PowerShell, Git and npm Codex are installed: `Get-Command node,pwsh,git,codex.cmd`.
2. Check sign-in with Codex's supported interactive CLI workflow **only if you authorize a Codex invocation**. No live CLI test is part of the mock gate.
3. Codex account/workspace identity, model catalog and rate-limit mapping must agree. The app refuses to guess when the live catalog or workspace identity is unavailable.
4. Existing registered jobs are unaffected by a failed GUI refresh. A quota reset display is informational, not permission to execute.

## "Shared session is not accessible" or TUI reconnects

First distinguish **real job completion** from an **owner crash**. The owner socket and `.shared.json` descriptor are transient. After normal cleanup, absence of the descriptor alone is **not** a failure.

Read the most recent saved outcome (this does not run Codex):

```powershell
$dir = Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
Get-ChildItem $dir -Filter 'CodexResume-*.result.json' -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 Name,LastWriteTime,
    @{n='Status';e={(Get-Content $_.FullName -Raw | ConvertFrom-Json).status}}
```

If the task reports `completed` and exit code 0, its scheduled **turn** finished. A Shared TUI should stay connected while attached in the new lifecycle implementation (until the bounded lifetime expires or the terminal exits). If it reconnects immediately on completion, collect the **exact application commit**, timestamps, outcome and a sanitized screenshot; this was the pre-fix BP204 defect.

## Check Windows Task Scheduler (read-only)

```powershell
Get-ScheduledTask -TaskName 'CodexResume-*' -ErrorAction SilentlyContinue |
  Select-Object TaskName,State
```

A **Running** Windows task can represent a Shared owner retaining the TUI client **after** the scheduled turn itself completed. A due-date countdown is not proof the task started. A background job can be blocked by account, branch, quota, missing conversation or mutex checks.

## Logs and results

Default directory: `%LOCALAPPDATA%\CodexResumeScheduler`.

- `CodexResume-<date>-<time>-<id>.json` — original scheduled job.
- `*.result.json` — persisted final outcome; `deferred` is **not** `completed`.
- Task transcript/log path is saved in the job JSON under `log` (not necessarily the same directory).
- `*.shared.json` — **temporary** owner descriptor; do not publish it. It may contain a local authentication secret.

To inspect the latest result without printing private prompts:

```powershell
$dir=Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
$f=Get-ChildItem $dir -Filter 'CodexResume-*.result.json' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($f){$x=Get-Content $f.FullName -Raw | ConvertFrom-Json; [pscustomobject]@{Job=$f.BaseName;Status=$x.status;ExitCode=$x.exitCode;At=$x.at;Message=$x.message} | Format-List}
```

Avoid uploading raw logs: they may contain prompts, environment paths, repositories, command output or session IDs.

## Preview build fails

- `Flutter SDK not on PATH`: ensure `flutter.bat` resolves from PowerShell `Get-Command flutter.bat`.
- Toolchain error: run `flutter doctor -v` and install Visual Studio Desktop development with C++.
- `Review package already exists`: the builder intentionally refuses to overwrite. Specify a **new** `-OutputDirectory`; do not manually mix binaries from different commits.
- CI green ≠ GUI accepted. Review on the actual signed-in Windows machine and verify package hashes.
- Antivirus warnings: do **not** disable security software, disable SmartScreen globally or add broad exclusions; unsigned preview distribution is an outstanding issue.

## If you report a bug

Include (1) source commit, (2) build/preview path, (3) execution mode and access, (4) expected/actual result, (5) task `status` and exit code, (6) sanitized screenshots. Leave out tokens, session IDs, raw `.shared.json` and private transcripts. [Current acceptance checklist](CONTINUUM-WINDOWS-ACCEPTANCE.md).