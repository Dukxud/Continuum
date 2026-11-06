# Flutter Windows Scheduler port — parity candidate

The Flutter interface now uses the **original approved Windows/Aero v1.16 source
pixels and GL optical program** (adapted to Flutter FragmentProgram coordinates
and premultiplied alpha), with an original-pixel fallback. It preserves the
v1.16 barAppearance settings, four independent colors, custom RGB choices,
liquid material and studio lighting, optical strength/speed, full/compact
window resizing, completed/history details and the existing secured worker.
The appearance dialog separates Colors and Optics into two visible tabs.
Each tab previews changes immediately; edits persist automatically, and
Done closes the editor without an additional Save action.

**Do not merge or publish from this branch.** Code and test coverage have been
authored and passed in earlier builds, but renewed native visual, sizing,
accessibility and real scheduling/cancellation acceptance on BLACK-PUDDLE
are required for this revision. See docs/FLUTTER-PARITY.md.

## Scheduled execution: native terminal or background

New Flutter schedules default to **Native terminal**, which resumes the
original Codex conversation in a real console with the configured model,
permissions, reasoning effort and saved instruction. Codex itself owns the
interactive UI; questions and approvals can be answered there. The existing
session-level mutex, account/workspace binding, repository branch check and
quota validation remain in effect. Terminal jobs still use one Windows Task
Scheduler action and remain Running until the console's Codex process exits.

Windows must have a signed-in interactive desktop. The scheduled launcher
opens PowerShell 7 with a visible console, which follows the configured
Windows default terminal application (including Windows Terminal if selected).
Closing the Codex TUI exits the run; Windows records **Finished** rather than
claiming the requested work is verified complete. The conversation's normal
Codex history is the authoritative source of its responses.

**Background** preserves the existing noninteractive `codex exec --json`
worker, machine-readable event stream and bounded quota auto-continuation.
The auto-continuation switch is unavailable in Native terminal mode. Existing
scheduled payloads without `executionMode` continue as background jobs.

This does **not** attach to a running hidden `exec` process or allow two
independent clients to write the same conversation simultaneously. A thread
still open in another Codex app must release its writer before the scheduled
resume can own it. The shared App Server multi-client design remains
experimental and is not substituted for these safety checks.

## Quota auto-resume — optional and bounded

The **Auto-resume if usage limits stop Codex** switch in the handoff is off by
default. When enabled for a **new** scheduled run, the pinned Windows worker may
register one new continuation at the verified exhausted-model reset + 60 seconds.
It keeps the session, account, Git repository, branch, model and permissions,
and refuses automatic continuation on generic errors or missing thread data.
Each continuation counts toward a hard maximum of **three** follow-ups.
**Waiting for quota** appears in the pending list and can be cancelled.
WinForms and existing jobs retain their original one-shot semantics; old
`autoResume` fields alone do not activate this feature.

This is a Windows Task Scheduler feature, not a Codex CLI flag. It requires an
interactive signed-in Windows desktop at execution time. It does not retry
indefinitely or guarantee quota becomes available. See
[`docs/QUOTA-CONTINUATION-DESIGN.md`](../docs/QUOTA-CONTINUATION-DESIGN.md).

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
