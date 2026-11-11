# Desktop application

Continuum's Flutter interface, Windows JSON bridge, and preview builder live here. The scheduled worker is in [../backend/](../backend/). The original interface is retained separately in [legacy/winforms/](../../legacy/winforms/).

## Code boundaries

| Source | Responsibility |
| --- | --- |
| `lib/main.dart`, `lib/app.dart` | Initialize the desktop host; configure the application theme and localization |
| `lib/scheduler_home.dart`, `lib/dashboard_*.dart` | Coordinate the window and compose Full, Monitor, and Micro layouts |
| `lib/scheduler_controller.dart`, `lib/schedule_time.dart` | Maintain application state and calculate schedule times |
| `lib/bridge.dart` | Adapter interface and shared JSON field/error helpers |
| `lib/windows_scheduler_adapter.dart` | Windows subprocess transport, source discovery, and timeouts |
| `lib/history_dialog.dart`, `lib/live_activity_dialog.dart`, `lib/shared_session_panel.dart` | Independently testable history, activity, and Shared views |
| `windows_bridge.ps1` | Decode requests and dispatch JSON responses |
| `bridge/` | Read models, scheduling, Shared actions, and preference handlers |

Dashboard layout parts share the home widget's state. Dialogs have explicit inputs and callbacks. The controller depends on the adapter interface; widgets and logic can be tested without starting PowerShell.

Flutter owns presentation and windowing. The bridge and pinned backend own task registration, identity checks, execution, and durable outcomes. macOS/Linux/web task execution is unimplemented. See [architecture](../../docs/ARCHITECTURE.md) and the [Shared session contract](../../docs/SHARED-NATIVE-TUI.md).

## Development checks

Use Windows x64, PowerShell 7, Node.js 22, Git, Flutter 3.47.9, Visual Studio's C++ desktop tools, and symbolic-link support for Flutter plugins. Codex is required for actual account interactions and executions. See [setup prerequisites](../../docs/GETTING-STARTED.md#prerequisites).

From the repository root with Flutter on PATH:

```powershell
npm ci --ignore-scripts
if ($LASTEXITCODE -ne 0) { throw 'Tool dependency installation failed.' }
npm test
if ($LASTEXITCODE -ne 0) { throw 'Node tests failed.' }
pwsh -NoProfile -STA -File .\src\desktop\Run-WindowsReview.ps1 -TestsOnly
if ($LASTEXITCODE -ne 0) { throw 'Desktop checks failed.' }
```

The review script checks the source and real bridge with isolated fixtures, generates the Windows runner, installs the pinned icon, restores the committed dependency lock, and runs strict analysis and Flutter tests. Without `-TestsOnly`, it also opens the debug app. Opening the app may query account metadata; tests do not request live model turns.

The [test guide](../../tests/README.md) documents the complete backend/component suite and coverage boundaries. Run `dart format lib test` from this directory after Dart edits. CI rejects formatting differences, analyzer findings, and widget taps that miss their targets.

## Build a preview

From the repository root:

```powershell
pwsh -NoProfile -STA -File .\src\desktop\Build-WindowsPreview.ps1 -OutputDirectory "$HOME\Downloads\Continuum-Main"
if ($LASTEXITCODE -ne 0) { throw 'Preview build failed.' }
$continuumExe = Join-Path $HOME 'Downloads\Continuum-Main\Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW\codex_resume_flutter.exe'
if (!(Test-Path -LiteralPath $continuumExe -PathType Leaf)) { throw 'Executable missing.' }
Start-Process -FilePath $continuumExe -WorkingDirectory (Split-Path -Parent $continuumExe)
```

The folder and ZIP names derive from `pubspec.yaml`; update the example path when that version changes. `pubspec.lock` pins application dependencies. The retained WinForms version in `legacy/winforms/VERSION` is independent.

The package includes the Flutter runtime, bridge handlers, backend, required components, license, `build-info.json`, and `SHA256SUMS.txt`. Build metadata records the application version, source commit, tracked working-tree changes, and UTC build time. The builder refuses to overwrite an existing package and verifies every manifest entry after extracting the ZIP. `-PackageVerifiedBuild` is reserved for isolated GitHub Actions builds.

## Branding and acceptance

The checked-in `branding/continuum.ico` is the icon authority. After runner generation, `scripts/Install-WindowsIcon.ps1` installs it and validates the resource reference. Generated runner files remain untracked.

A green build establishes source and package checks, not native behavior. The [acceptance ledger](../../docs/CONTINUUM-WINDOWS-ACCEPTANCE.md) records observations and pending live checks. The [current state](../../docs/CURRENT-STATE.md) retains earlier build evidence. Include the exact source SHA, checksum, download or launch command, and verification scope with a review build.
