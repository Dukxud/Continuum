# Continuum troubleshooting

Start by identifying the executable and checking its dependencies. The commands below inspect the local environment without scheduling work. See [current state](CURRENT-STATE.md) for recorded builds and known limitations.

## Identify the running version

The default output from [Getting started](GETTING-STARTED.md) is:

```text
%USERPROFILE%\Downloads\Continuum-Preview\Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW\codex_resume_flutter.exe
```

Downloaded review packages have different paths; the [build record](CURRENT-STATE.md#source-layout-preview--11-nov-2026) identifies the verified source-layout preview. The public v1.11.0 release contains the older WinForms app. A GitHub merge does not update an installed executable. Keep each complete package together, including its workers and DLLs.

To inspect the running executable's path:

```powershell
Get-Process -Name codex_resume_flutter -ErrorAction SilentlyContinue |
    Select-Object Id,Path
```

New packages include `build-info.json` beside the executable with the application version, source commit, build time, and whether tracked source files were modified. For an older package, use its recorded source SHA and checksum. In a source checkout, `git log -1 --format="%H %s"` identifies the commit; `git status --short` shows local changes.

## Build prerequisites

Run `flutter doctor -v` and resolve Windows toolchain errors. The builder requires `flutter.bat` on `PATH` and Visual Studio's **Desktop development with C++** workload.

If runner generation reports **Building with plugins requires symlink support**, enable [Windows Developer Mode](https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode) on the build machine, then rerun the build. This requirement was encountered during the source-layout review; the same revision passed on the hosted Windows builder.

If the builder reports **Review package already exists**, choose a fresh `-OutputDirectory`. It preserves existing packages. If a CI artifact has expired, use the [source-build instructions](GETTING-STARTED.md).

## Weekly appears as five-hour, or a phantom empty row

This was a positional-label bug corrected in PR #22. Current source displays the returned label and window count in Full, Monitor, and Micro. Confirm the running EXE's path: an older package can still show the previous behavior after a source merge.

No usage windows, unknown resets and unavailable reads are different states; do not infer unlimited capacity or a new plan entitlement. Check the selected model and wait for the app's ordinary read-only refresh. [Display contract](QUOTA-PRESENTATION.md).

## Warning triangle in title bar

PR #21 corrected the native icon by installing the Continuum ICO after Windows runner generation. The corrected title-bar icon was observed in Micro view. Check that you launched a package containing that correction. The old triangle alone did not establish a security warning, and the cause of the original substitution was not proven. [Visual evidence](SCREENSHOTS.md).

## Missing model, usage or disabled schedule

Check dependencies without running a model turn:

```powershell
Get-Command node,pwsh,git,codex.cmd -ErrorAction Stop | Select-Object Name,Source
```

Confirm that the installed npm Codex CLI is signed in to the intended account. The app needs a verified workspace, a supported model and reasoning effort, and a current model-matched quota response. Exhausted quota can still permit scheduling for a future time; the worker checks availability again when the job starts. An unavailable or ambiguous metadata response can block scheduling. Inspect the displayed reason and allow the ordinary refresh to complete.

## Shared terminal reconnects

The original Shared implementation closed the owner after the scheduled turn, disconnecting its terminal. Current source retains a successful owner for attached clients, with a 15-second no-viewer grace and a two-hour cap. Live verification of this retention behavior remains pending. Later TUI turns are not continuously mirrored by the current host.

Inspect the **specific** job being investigated; do not assume the newest result belongs to it:

```powershell
$dir=Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
Get-ChildItem $dir -Filter 'CodexResume-*.result.json' -File |
  Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name,LastWriteTime
# Replace with the exact affected task name:
$name='CodexResume-YYYYMMDD-HHMM-xxxxxxxx'
$path=Join-Path $dir ($name+'.result.json')
if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Select-Object status,exitCode,at,message}
```

A removed `.shared.json` after cleanup is expected. While a native lease retains the owner, Task Scheduler can still show Running even though the scheduled turn is completed and final disk result is not yet written. An unavailable owner without a result is not automatically success.

```powershell
Get-ScheduledTask -TaskName 'CodexResume-*' -ErrorAction SilentlyContinue | Select-Object TaskName,State
```

## Report a problem

Include the source SHA or package identity, Windows and Codex CLI versions, execution mode, steps to reproduce, and expected versus observed behavior. Include the affected job's sanitized outcome when available. Remove private paths, tokens, raw session IDs, and conversation content before posting. See [security and privacy](SECURITY-AND-PRIVACY.md) and [contributing](CONTRIBUTING.md).
