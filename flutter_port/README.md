# Scheduler Flutter Windows review (unmerged)

This is a **real Flutter desktop client** for the existing Windows Scheduler, not an image or simulated scheduler. It reads local Codex sessions, repository evidence, live model/usage catalog, Windows Task Scheduler jobs, and saved run evidence. Scheduling and cancellation call the existing verified PowerShell 7 modules. A newly created one-time task still pins and fingerprints the **v1.16 worker**, rechecks selected-workspace identity, and never automatically retries.

## Windows review

1. Install the **stable Flutter SDK** and Visual Studio with **Desktop development with C++**, following https://docs.flutter.dev/platform-integration/windows/setup and https://docs.flutter.dev/install. Run flutter doctor -v; verify Windows desktop support.
2. Clone/checkout branch feat/flutter-windows-review-v0 and run from repo root: pwsh -NoProfile -File .\flutter_port\Run-WindowsReview.ps1
3. Tests run first; on success Flutter builds and opens the Windows desktop client.

The Flutter toolchain generates the native Windows runner on first launch. No prebuilt binary, installer, code-signing certificate, GitHub Actions job, or production release is included. Existing v1.16 Windows UI remains available.

**Review caution:** Do not concurrently edit settings in the WinForms and Flutter applications. Both currently use the existing %LOCALAPPDATA%\CodexResumeScheduler settings and job history. Use a disposable saved Codex conversation for a real execution test.

## Verified architectural boundary / limitations

- Flutter UI and pure Dart scheduling-time math are platform-neutral.
- The **only implemented backend adapter is Windows**: flutter_port/windows_bridge.ps1. macOS, Linux and browser execution will need native scheduling/worker adapters, plus platform-specific security and lifecycle acceptance.
- The Flutter liquid tube is a native CustomPainter **approximation**, not a pixel-identical port of the WebView2/WebGL2 shader. The core scheduling behavior is kept; optical effects and the full appearance editor are not yet parity-complete. Test UI visually before accepting it as a replacement.
- The bridge intentionally reruns fresh catalog/quota verification, canonical workspace checks, repository and branch validation, overlap checks and pinned-worker creation at task registration time.
- This is an **experimental candidate**; no on-device Flutter build or executable acceptance has been claimed.

## Scope

Implemented: session picker and repository lookup/browse, live model/effort/quota selection, one-shot task creation, cancellation, countdown, running indicators, compact mode, persistent draft, basic color appearance, saved history, copy response/log, display-only history removal, log-folder opening, automatic task polling. Existing worker semantics are unchanged.

Deferred: macOS/Linux/web adapters, full optics parity with the established shader, production signing, and distribution packaging. Flutter and PowerShell integration must be independently verified on BLACK-PUDDLE before merging.
