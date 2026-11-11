# Continuum Flutter Windows developer guide

This directory contains Continuum's Flutter desktop interface, Windows JSON bridge, tests, and preview builder. The active backend is in [src/backend/](../src/backend/); the older interface is in [legacy/winforms/](../legacy/winforms/). Feature development is paused. See [current state](../docs/CURRENT-STATE.md) for recorded builds and outstanding verification.

## Implemented boundaries

Flutter supplies Full/Monitor/Micro windows, pinning, date/time entry, history and appearance. `windows_bridge.ps1` validates JSON and delegates Windows operations; `src/backend/CodexRunEngine.ps1` and immutable runtime snapshots own unattended execution. The GUI is not a replacement worker. macOS/Linux/web execution remains unimplemented.

Background uses noninteractive execution and optional bounded quota-only continuation. Native terminal launches the ordinary CLI TUI. Shared owns one App Server and allows authenticated native TUI clients; it cannot take over an arbitrary preexisting CLI. Post-completion retention does not make the GUI a continuous multi-turn observer. [Shared details](../docs/SHARED-NATIVE-TUI.md).

All modes display actual returned quota windows. The same presentation handles Plus or Pro: singleton Weekly, singleton five-hour, two windows, unfamiliar labels and honest empty/error states. Appearance follows meaning, not list index. No scheduling/account policy changed. [Contract](../docs/QUOTA-PRESENTATION.md).

## Requirements and local checks

Use Windows x64, a standard PowerShell 7 installation, Node.js, Git, and npm Codex for runtime. Builds also require Flutter, Visual Studio's C++ desktop workload, and Windows symbolic-link support for plugins. See [Getting started](../docs/GETTING-STARTED.md#prerequisites) for prerequisites and [troubleshooting](../docs/TROUBLESHOOTING.md#build-prerequisites) for setup failures. Windows preflight pins Flutter 3.47.9; the Node workflows pin Node 22. The recorded native CLI capability check used 0.166.0; compatibility with other CLI versions requires verification.

From a complete checkout with `flutter.bat` on PATH:

```powershell
node --test tests/shared-codex-session.test.mjs tests/shared-codex-remote.test.mjs
if($LASTEXITCODE -ne 0){throw 'Mock tests failed'}
pwsh -NoProfile -STA -File .\flutter_port\Run-WindowsReview.ps1 -TestsOnly
if($LASTEXITCODE -ne 0){throw 'Windows/Flutter checks failed'}
```

Without `-TestsOnly`, the review script also launches the debug GUI. It checks source/bridge, generates the runner, installs the pinned icon, resolves dependencies, analyzes and tests once. Mock checks do not run real Codex tasks; startup GUI metadata/usage queries are distinct from a model turn.

## Build and exact output

```powershell
pwsh -NoProfile -STA -File .\flutter_port\Build-WindowsPreview.ps1 -OutputDirectory "$HOME\Downloads\Continuum-Main"
if($LASTEXITCODE -ne 0){throw 'Build failed'}
$p=Join-Path $HOME 'Downloads\Continuum-Main\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe'
if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw 'Executable missing'}
Start-Process -FilePath $p -WorkingDirectory (Split-Path -Parent $p)
```

This outputs a complete folder and ZIP, not a signed installer. It refuses existing destinations; choose a unique output for another review. The package retains Flutter runtime, workers, bridge, components and `SHA256SUMS.txt`; every manifest entry is checked after extracting the produced ZIP. `-PackageVerifiedBuild` is reserved for isolated Actions builds.

The [source-layout preview record](../docs/CURRENT-STATE.md#source-layout-preview--11-nov-2026) contains the verified PR #24 artifact, source SHA, checksums, download command, and exact executable path. CI downloads expire; the command above builds a fresh package from your checkout.

## Native icon and test entrypoints

Generated `windows/runner` files are not the branding authority. After `flutter create`, `scripts/Install-WindowsIcon.ps1` copies checked-in `branding/continuum.ico` and validates the resource reference. Both local launch/build paths and Flutter preflight CI apply it before compilation. `tests/flutter-windows-icon.test.ps1` verifies the generated resource and compiled EXE; actual Micro title-bar acceptance was supplied for BP210.

`test/quota_windows_test.dart` covers returned-window rendering with in-memory adapters; `test/window_mode_test.dart` and `test/widget_test.dart` retain cross-view/error coverage. No live task is needed for the quota visual check. Node Shared protocol tests use a fake App Server. See [acceptance ledger](../docs/CONTINUUM-WINDOWS-ACCEPTANCE.md) for what is still pending rather than treating a green build as universal acceptance.

Include the exact source SHA, package checksum, download or launch command, and verification scope with each review build. See [contributing](../docs/CONTRIBUTING.md) for review expectations and [release policy](../docs/RELEASE-POLICY.md) for publication requirements.
