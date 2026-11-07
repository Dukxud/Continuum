# Continuum troubleshooting

**Paused baseline:** [CURRENT-STATE.md](CURRENT-STATE.md). All diagnostics below are read-only unless explicitly described otherwise. Do not start a live Codex turn merely to diagnose the UI.

## Which binary?

BP211 is the latest application preview recorded at pause. Its normal extraction path is:

```text
%USERPROFILE%\Downloads\Continuum-BP211-QuotaFix\Unpacked\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe
```

BP210 fixed the icon; BP211 also contains the quota correction. BP208 cloned source but did not compile a separate EXE. `Continuum-Main` is a local build output, not automatically updated by a GitHub merge. The public v1.11.0 release is WinForms. Documentation commits do not rebuild an installed program. Keep the whole package; do not mix workers/DLLs between previews.

For source identity: `git -C <checkout> log -1 --format="%H %s"`. For building/reopening, see [Flutter guide](../flutter_port/README.md).

## Weekly appears as five-hour, or a phantom empty row

This was the positional-label bug corrected in #22. BP211 displays the returned label/count in Full, Monitor and Micro for both Plus and Pro, without checking tier names. An older running EXE can continue showing the old layout even after source is merged. Confirm its path before concluding the fix failed.

No usage windows, unknown resets and unavailable reads are different states; do not infer unlimited capacity or a new plan entitlement. Check the selected model and wait for the app's ordinary read-only refresh. [Display contract](QUOTA-PRESENTATION.md).

## Warning triangle in title bar

The earlier new-versus-old screenshots established a visual regression. Equal `ExtractAssociatedIcon` hashes did not prove identical live title-bar icons or identify the cause. PR #21 pins the Continuum ICO after runner generation; BP210's Micro screenshot confirms the corrected native icon. Inspect the running binary's path before clearing Windows caches or changing OS security settings. The image alone did not establish an application/security warning.

## Missing model, usage or disabled schedule

Check dependencies without running a model turn:

```powershell
Get-Command node,pwsh,git,codex.cmd -ErrorAction Stop | Select-Object Name,Source
```

The worker requires verifiable workspace identity, applicable quota and a supported model/effort. A failed/ambiguous metadata read cannot safely be replaced by guessed model/plan values. Separately authorize any Codex sign-in/version/real-task invocation when needed. Do not disable safeguards to bypass a blocked job.

## Shared terminal reconnects

The original task completed but owner shutdown dropped its TUI. The retention fix keeps a successful Shared owner alive for attached leases, with 15-second no-viewer grace and a two-hour cap. Its fixed live behavior remains a pending acceptance item. Later TUI turns are not continuously mirrored by the current host.

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

## Build failures and reports

`flutter.bat` must resolve; `flutter doctor -v` diagnoses build prerequisites. The preview builder refuses existing output folders; use a fresh `-OutputDirectory`, not files copied over a previous build. Artifact expiry requires a source rebuild, not an invented download URL. Preview binaries are unsigned; do not disable antivirus or broadly exclude directories.

Report exact SHA/package/EXE path, mode, expected/observed behavior and the affected job's sanitized outcome. Exclude tokens, personal paths, raw session IDs and full transcripts. [Security](SECURITY-AND-PRIVACY.md), [acceptance](CONTINUUM-WINDOWS-ACCEPTANCE.md).
