# Getting started

This guide builds the current Flutter version of Continuum from source on Windows. The published [v1.11.0 ZIP](https://github.com/Dukxud/Continuum/releases/tag/v1.11.0) contains the earlier WinForms application.

## Prerequisites

| Dependency | Requirement |
| --- | --- |
| Windows | x64, with a signed-in desktop session |
| PowerShell | PowerShell 7 in its standard `C:\Program Files\PowerShell\7` location |
| Node.js and Git | Available on `PATH`; the recorded CI baseline uses Node 22 |
| Codex CLI | npm installation, signed in to the account you intend to use |
| Flutter | `flutter.bat` available on `PATH`; CI pins Flutter 3.47.9 |
| Visual Studio | Desktop development with C++ workload and Windows build tools |
| Windows build permissions | Symbolic-link support for Flutter plugins; enable [Developer Mode](https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode) on the build machine if Flutter requests it |

The pinned versions describe the recorded build environment. Compatibility with a different Codex CLI or SDK version should be checked before scheduling work. See the [developer guide](../src/desktop/README.md) for the verification commands.

Before building, run `flutter doctor -v` and resolve any Windows toolchain errors. See [troubleshooting](TROUBLESHOOTING.md#build-prerequisites) if runner generation reports that symlink support is missing.

## Build the preview

Run the following in **PowerShell 7**. It creates a new checkout under your user profile, then builds and verifies a complete Windows package. It does not launch the app or schedule a job.

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

After a successful build, run this in PowerShell 7:

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
