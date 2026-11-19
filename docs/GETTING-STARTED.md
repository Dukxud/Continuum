# Getting started

The [Windows engineering preview](https://github.com/Dukxud/Continuum/releases/tag/v0.1.0-preview.1) is available as a ready-to-run ZIP. You can also build the current Flutter application from source. The older [v1.11.0 ZIP](https://github.com/Dukxud/Continuum/releases/tag/v1.11.0) contains the WinForms application.

## Download and run

If you downloaded a **complete repository source ZIP**, extract it and double-click `Run-Continuum.cmd` at its root on Windows x64. The same command also works in a Git checkout or worktree. It builds that folder's current source, verifies the complete package, then starts the resulting application under `%LOCALAPPDATA%\Continuum\SourceBuilds\<unique-id>`. Every source launch makes a fresh package. The compatible toolchain and symbolic-link permission listed below must already be available; the launcher does not install SDKs, change Windows settings or substitute an older application.

**Reviewing a PR from source:** Download the complete source archive for that PR's branch or commit, extract it, and use the same `Run-Continuum.cmd`. A source archive does not need Git metadata to build. The optional `-BuildFromSource` PowerShell switch remains available, but is unnecessary for a complete source tree. No GitHub Actions run is required for this route.

**Opening a complete Windows review package:** Extract it and double-click `Run-Continuum.cmd` beside `codex_resume_flutter.exe`. A runtime-only folder opens its own application after verifying `SHA256SUMS.txt`. Complete source takes precedence over a stray sibling executable; incomplete source or runtime packages fail with an explicit error.

The launcher prints the executable, build identity and effective backend path before starting it. It unblocks only allowlisted source scripts or verified package files, rejects linked source script paths, and does not change execution policy. Its pinned-preview fallback also requires the supplied package verifier; copying only the two launcher files is rejected. Keep the complete source or application package together for review.

Current release builds use the backend and bridge beside their own executable, including when the EXE is opened directly. They do not search parent checkouts or the launch working directory for missing files. An intentional `CODEX_SCHEDULER_SOURCE` override must identify a complete backend and bridge; a relative override resolves once from the app's working directory at startup and becomes absolute. The normal launcher starts the app in its package directory. An invalid override stops startup with an error. Remove a stale override before opening the bundled application.

1. Download `Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW.zip` from the [preview release](https://github.com/Dukxud/Continuum/releases/tag/v0.1.0-preview.1).
2. Extract the complete ZIP to a new folder. Keep its DLLs, `data`, `src`, and `components` folders beside the executable.
3. Open `codex_resume_flutter.exe`. Windows x64, PowerShell 7 in its standard installation location, Node.js, Git, the [Microsoft Visual C++ v14 Redistributable (x64)](https://aka.ms/vc14/vc_redist.x64.exe), and an installed, signed-in npm Codex CLI are required.

Flutter, Visual Studio and permission to create plugin symbolic links are source-build prerequisites; they are not required for running the downloaded package. Developer Mode normally supplies that link permission for an ordinary Windows user. The preview is unsigned; read its release notes for known limitations. `SHA256SUMS.txt` on the release page verifies the downloaded ZIP, and the manifest inside the package covers its individual files.

For source builds, continue below.

## Prerequisites

| Dependency | Requirement |
| --- | --- |
| Windows | x64, with a signed-in desktop session |
| PowerShell | PowerShell 7.4 or newer for current source and its runtime helpers |
| Node.js and Git | Node.js 22 or newer and Git 2.28 or newer on `PATH`; the source-build bridge check uses `git init -b` |
| Codex CLI | Current source accepts the official native `codex.exe` or npm installation on `PATH`, signed in to the account you intend to use |
| Flutter/Dart | Flutter 3.47.9 with its bundled Dart 3.13.7; `flutter.bat` on `PATH`. The preflight checks this Flutter version, the app's Dart `>=3.13.0 <4.0.0` requirement and the SDK files; dependencies retain the committed lock |
| Visual Studio | Desktop development with C++ workload, MSVC x64/x86 tools, CMake tools and Windows SDK; finish installation and any requested reboot |
| Windows build permissions | Actual symbolic-link creation must work in the source location. For error 1314, enable [Developer Mode](https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode) in Windows Settings and rerun the same launcher |
| Scheduled-job host | Working Windows Script Host and VBScript engine; the source preflight checks a disposable script that only exits with a known code |

The source build requires the pinned Flutter version and leaves installed SDKs unchanged. Compatibility with a different Codex CLI should be checked before scheduling work. See the [developer guide](../src/desktop/README.md) for the verification commands.

The current source resolves both supported [Codex CLI installation forms](https://learn.chatgpt.com/docs/codex/cli). Node.js remains necessary for Continuum's metadata and Shared helpers even with native Codex. Restart Continuum after changing `PATH`. The older pinned public preview above predates this resolver change and retains its recorded npm prerequisite.

Before building, run `flutter doctor -v` and resolve the **Windows version** and **Visual Studio - develop Windows apps** findings. Flutter's [Windows setup guide](https://docs.flutter.dev/platform-integration/windows/setup) describes this toolchain; Visual Studio Code alone does not provide it. An overall doctor result also includes other platforms and is not proof of Windows readiness.

The preflight reports independent missing prerequisites together before starting the build. If Flutter cannot run, it reports that the dependent plugin-link probe could not run rather than claiming that capability passed. A missing VBScript engine is handled through Windows **Optional features**, subject to the machine's policy; see [Microsoft's feature guidance](https://techcommunity.microsoft.com/blog/windows-itpro-blog/vbscript-deprecation-timelines-and-next-steps/4148301).

If Flutter reports **Building with plugins requires symlink support**, open Windows Settings with `ms-settings:developers`, enable Developer Mode, then rerun `Run-Continuum.cmd`. Enabling that setting requires the permissions allowed by your machine's administrator or organization; the launcher cannot grant them. [Troubleshooting](TROUBLESHOOTING.md#build-prerequisites) distinguishes this privilege failure from other filesystem errors.

Keep the source in a writable Windows location with a simple path. Flutter 3.47.9 rejects project-path characters `'#!$^&*=|,;<>?` because of CMake/MSBuild escaping; spaces and parentheses are allowed. Preserve the committed `pubspec.lock`. Package downloads or later compiler errors require their own diagnosis even after prerequisites pass.

Windows desktop support must be enabled in Flutter, and its configured build directory must resolve to the project's `build` folder. The preflight reports a conflicting project, global or environment setting and its recovery command; it does not change Flutter configuration. A relative `PUB_CACHE` resolves from `src/desktop`.

## Build the preview

Run the following in **PowerShell 7.4 or newer**. It creates a new checkout under your user profile, then builds and verifies a complete Windows package. It does not launch the app or schedule a job.

```powershell
$ErrorActionPreference = 'Stop'
$continuumRepo = Join-Path $HOME 'source\continuum'
$continuumOutput = Join-Path $HOME 'Downloads\Continuum-Preview'

if (Test-Path -LiteralPath $continuumRepo) {
    throw 'This checkout already exists. Use it deliberately or choose a new path.'
}
New-Item -ItemType Directory -Path (Split-Path -Parent $continuumRepo) -Force | Out-Null
git clone --branch main --single-branch https://github.com/Dukxud/Continuum.git $continuumRepo
if ($LASTEXITCODE -ne 0) { throw 'Clone failed.' }

Set-Location -LiteralPath $continuumRepo
pwsh -NoProfile -STA -File .\src\desktop\Build-WindowsPreview.ps1 -OutputDirectory $continuumOutput
if ($LASTEXITCODE -ne 0) { throw 'Preview build failed.' }
```

The builder generates the Windows runner, installs the checked-in icon, runs source/bridge checks and Flutter analysis/tests, compiles the app, and verifies the extracted ZIP against its checksum manifest. It refuses to overwrite an existing preview package; choose a fresh output directory for a subsequent build.

## Open the app

After a successful build, run this in PowerShell 7.4 or newer:

```powershell
$continuumExe = Join-Path $HOME 'Downloads\Continuum-Preview\Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW\codex_resume_flutter.exe'
if (!(Test-Path -LiteralPath $continuumExe -PathType Leaf)) {
    throw 'Executable not found. Confirm the build succeeded and check its output path.'
}
Start-Process -FilePath $continuumExe -WorkingDirectory (Split-Path -Parent $continuumExe)
```

If you selected a different output directory, update the launch path to match. The package version comes from `src/desktop/pubspec.yaml`; the example below uses `0.1.0+1`. The executable's default location is:

```text
%USERPROFILE%\Downloads\Continuum-Preview\Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW\codex_resume_flutter.exe
```

Keep the complete package together, including its DLLs, `data` folder, bridge, and worker files. Opening Continuum may query account, conversation, model, and usage metadata. A model turn starts only when an execution is requested.

## First use

1. Choose a saved Codex conversation and confirm its repository and branch. Use a disposable conversation for an initial trial.
2. Select a model, access level, and execution mode.
3. Enter a time and instruction, then select **Schedule once** when ready to run the job.
4. Keep Windows awake, online, and signed in when the task is due. Check live activity and History for the execution outcome.

See the [user guide](USER-GUIDE.md) for mode-specific behavior and cancellation limits. Closing Continuum does not cancel registered tasks.

## Preview status

The Flutter package is an unsigned engineering preview. Feature development is paused, and Shared retention/approval behavior and the latest live quota display still have outstanding native checks. See [Windows acceptance](CONTINUUM-WINDOWS-ACCEPTANCE.md).

Previously built review packages are documented in the [project status](CURRENT-STATE.md). Their CI downloads expire; this source-build guide is the durable setup path. The [release policy](RELEASE-POLICY.md) describes the remaining requirements for a signed production release.
