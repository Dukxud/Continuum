# Continuum architecture

Continuum separates the Flutter desktop interface from Windows scheduling and execution. A JSON bridge connects the UI to a pinned PowerShell worker, with reusable modules for persistence, task registration, and outcomes. See the [maintainer handoff](CURRENT-STATE.md) for the current baseline and [project history](history/ARCHITECTURE-WINFORMS.md) for the original WinForms design.

## Runtime boundaries

```text
Flutter desktop UI
  -> WindowsSchedulerAdapter (JSON subprocess boundary)
  -> flutter_port/windows_bridge.ps1
  -> Windows Task Scheduler + immutable worker snapshot
  -> src/backend/Invoke-CodexJob.ps1
  -> src/backend/CodexRunEngine.ps1 (identity/repository/model/quota/mutex checks)
       Background: codex exec --json
       Native: ordinary Codex CLI TUI
       Shared: one App Server + authenticated local clients
```

| Layer | Source | Responsibility |
| --- | --- | --- |
| Application/window | `flutter_port/lib/main.dart`, `desktop_window.dart` | Full/Monitor/Micro, native window size/pin/close coordination |
| State/adapter | `scheduler_controller.dart`, `bridge.dart` | Refresh, draft state, JSON calls; not a duplicate unattended worker |
| Quota display | `dashboard_monitor.dart`, `dashboard_frame.dart`, `dashboard_micro.dart` | Actual window labels/counts and values, neutral empty states, shared Full/Monitor rendering |
| Windows boundary | `flutter_port/windows_bridge.ps1` | Validate request, persist/register/cancel/query jobs, shared status and terminal actions |
| Metadata/usage | `src/backend/CodexUsage.js`, session/repository readers | Codex-supported account/model/rate/thread metadata; no prompt just to refresh quota |
| Worker | `src/backend/CodexRunEngine.ps1`, `src/backend/CodexQuotaContinuation.ps1`, `src/backend/CodexTerminalRun.ps1` | Pinned execution checks, original conversation, bounded retry, durable result |
| Shared session | `components/SharedCodexSession/{main,host,remote,client,protocol}.mjs` | One App Server, pipe authentication, remote TUI credentials, requests and scheduled-turn lifecycle |
| Generic services | `components/RuntimeBundle`, `OneTimeTasks`, `GitRepository`, `JobOutcomes`, `SettingsStore` | Independently scoped persistence/validation/infrastructure |

## Source layout

The active PowerShell backend lives in [src/backend/](../src/backend/), while [legacy/winforms/](../legacy/winforms/) contains the original UI and its launchers. The scheduled entry point, `src/backend/Invoke-CodexJob.ps1`, loads the worker directly without loading the legacy interface. Shared and reusable modules remain in `components/`; Flutter remains in `flutter_port/`.

Packages and new immutable worker snapshots preserve these repository-relative paths. Their root is resolved from the entry script, independently of the process working directory. Previously scheduled jobs keep their existing snapshot and launch paths.

## Quota data is not position or subscription tier

The usage reader selects a model-attributed bucket, normalizes primary/secondary windows and labels their reported duration. The presentation uses the returned list directly. Weekly can be the only or first window. No `Plus`/`Pro` special case was introduced; the same code renders a singleton or pair. This does not change permissions, quota enforcement or continuation eligibility. [Exact contract](QUOTA-PRESENTATION.md).

## Execution and persistence

The bridge registers one-time Windows tasks. Jobs retain their original immutable content-addressed runtime; upgrades do not rewrite existing jobs. The worker validates the pinned runtime, Git root/branch, selected workspace/model/effort, available quota and per-conversation scheduler mutex before execution. The mutex prevents competing scheduler workers, not every independently launched Codex process.

Local state lives under `%LOCALAPPDATA%\CodexResumeScheduler`: settings, saved job JSON, runtime snapshots, result records and references to transcripts. `*.result.json` distinguishes completed, finished, failed, blocked, deferred and cancelled. Settings and logs may contain private data. Closing the UI or pausing development does not cancel registered tasks.

Only Background mode supports explicit, off-by-default quota-only continuation, capped at three follow-ups with verified reset/account/model evidence. Native and Shared do not silently inherit it. [Design](QUOTA-CONTINUATION-DESIGN.md).

## Shared owner lifetime

Continuum starts the owner for the saved conversation. GUI clients use its authenticated named pipe; a user-requested native TUI is a remote client of the same authenticated loopback App Server. This is not attachment to an arbitrary already-running CLI.

After the scheduled turn completes successfully, native TUI leases can retain the server. No lease triggers a 15-second grace; retention is capped at two hours. The worker/mutex remains held, and durable job result is written when the host exits. Flutter reads the live scheduled-turn status or falls back to the durable result after cleanup.

**Important limit:** `onAppMessage` stops processing after the scheduled turn is completed. Retaining a TUI is not full multi-turn GUI mirroring. Future-turn approvals, server loss after completion and cap expiry during later work require review/native tests. [Shared contract](SHARED-NATIVE-TUI.md).

## Build and native icon

`flutter_port/Build-WindowsPreview.ps1` and `flutter_port/Run-WindowsReview.ps1` generate the Windows runner, then install the checked-in `flutter_port/branding/continuum.ico` via `flutter_port/scripts/Install-WindowsIcon.ps1` before compilation. The release package includes the Flutter runtime, backend, bridge, required components, and checksum manifest. See [Windows acceptance](CONTINUUM-WINDOWS-ACCEPTANCE.md) for build and native icon verification.

Flutter UI portability is not worker portability: macOS/Linux/web task execution is unimplemented. This is an unsigned Windows engineering preview, not a production release. [Security](SECURITY-AND-PRIVACY.md) and [release policy](RELEASE-POLICY.md).
