# Flutter Windows Scheduler port — parity candidate

The Flutter interface now uses the **original approved Windows/Aero v1.16 source
pixels and GL optical program** (adapted to Flutter FragmentProgram coordinates
and premultiplied alpha), with an original-pixel fallback. It preserves the
v1.16 barAppearance settings, four independent colors, custom RGB choices,
liquid material and studio lighting, optical strength/speed, full/compact
window resizing, completed/history details and the existing secured worker.

**Do not merge or publish from this branch.** Code and test coverage have been
authored, but compiling the revised shader and validating all behavior on
BLACK-PUDDLE are still required. See docs/FLUTTER-PARITY.md.

## Run (Windows review)

1. Install Flutter stable (3.47+), Visual Studio C++ desktop toolchain,
   PowerShell 7, Node, Git and npm Codex CLI.
2. Clone/fast-forward branch feat/flutter-windows-review-v0.
3. Run from the checkout:

    pwsh -NoProfile -STA -File .\flutter_port\Run-WindowsReview.ps1

The bounded command runs a PowerShell source/asset integrity check, Flutter
dependency resolution, Dart analyzer and Flutter tests **once**, then starts
the native Windows desktop GUI. A failed check stops launch; no CI loop.

## Standalone unsigned local engineering preview

    pwsh -NoProfile -STA -File .\flutter_port\Build-WindowsPreview.ps1

The script builds an unsigned release-mode Flutter executable and copies the
**original pinned worker sources and required components** beside the executable.
The archive is written under Downloads. It does not publish a GitHub release,
disable antivirus or change existing scheduled jobs.

## Platform boundary

Flutter UI, appearance model and optical renderer are cross-platform.
The Windows bridge still uses Task Scheduler, Windows PowerShell paths and
Codex's npm entrypoint. macOS/Linux/web workers are **not implemented**;
neither a Flutter build nor Windows parity establishes those capabilities.

Read and follow the acceptance matrix before treating the port as complete:
docs/FLUTTER-PARITY.md.
