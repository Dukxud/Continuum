# Continuum architecture

**Current authority:** merged `main`; [pause/baseline record](CURRENT-STATE.md). The older WinForms architecture is preserved separately in [history](history/ARCHITECTURE-WINFORMS.md).

## Runtime boundaries

```text
Flutter desktop UI
  -> WindowsSchedulerAdapter (JSON subprocess boundary)
  -> flutter_port/windows_bridge.ps1
  -> Windows Task Scheduler + immutable worker snapshot
  -> CodexRunEngine.ps1 (identity/repository/model/quota/mutex checks)
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
| Metadata/usage | `CodexUsage.js`, session/repository readers | Codex-supported account/model/rate/thread metadata; no prompt just to refresh quota |
| Worker | `CodexRunEngine.ps1`, `CodexQuotaContinuation.ps1`, `CodexTerminalRun.ps1` | Pinned execution checks, original conversation, bounded retry, durable result |
| Shared session | `components/SharedCodexSession/{main,host,remote,client,protocol}.mjs` | One App Server, pipe authentication, remote TUI credentials, requests and scheduled-turn lifecycle |
| Generic services | `components/RuntimeBundle`, `OneTimeTasks`, `GitRepository`, `JobOutcomes`, `SettingsStore` | Independently scoped persistence/validation/infrastructure |

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

`Build-WindowsPreview.ps1` and `Run-WindowsReview.ps1` generate the Windows runner, then install the checked-in `flutter_port/branding/continuum.ico` via `scripts/Install-WindowsIcon.ps1` before compilation. The release package includes runtime, workers, bridge and manifest, not just the EXE. The icon has native Micro screenshot acceptance in BP210. Its former warning-triangle substitution was not diagnosed by the equal extracted EXE hashes.

Flutter UI portability is not worker portability: macOS/Linux/web task execution is unimplemented. This is an unsigned Windows engineering preview, not a production release. [Security](SECURITY-AND-PRIVACY.md) and [release policy](RELEASE-POLICY.md).
