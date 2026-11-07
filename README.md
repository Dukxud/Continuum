# Continuum — Codex Resume Scheduler

Schedule a saved Codex conversation on Windows, monitor its usage and job status, and optionally open the real Codex terminal on a Shared execution owner.

**Engineering preview. Development is paused at the owner's request.** `main` is the retained baseline, with the native icon fix and response-driven quota display merged. Start with **[current state and restart handoff](docs/CURRENT-STATE.md)** for commits, verification boundaries and the exact executable location. This is an independent community project, not an OpenAI product.

## What is included

Full, Monitor and Micro windows; native Always on Top; customizable Aero-inspired bars; manual scheduling and saved drafts; pinned worker/runtime integrity; account/model/repository checks; history/results; and three execution modes:

| Mode | Execution owner / interaction | Quota-only continuation |
| --- | --- | --- |
| Background | Pinned noninteractive worker; structured logs/results | Optional, off by default, up to three eligible follow-ups |
| Native terminal | Ordinary Codex CLI TUI owns the interactive run | No |
| Shared session | One App Server; Continuum panel plus optional native remote TUI client | No |

Shared attaches only to a session **started by Continuum**, not any independently running Codex process. Successful scheduled completion can retain an attached TUI with a 15-second no-viewer grace and two-hour cap. Later TUI turns are not continuously mirrored by the current host. Retained live attachment and simultaneous approvals still have pending native tests. [Full Shared contract](docs/SHARED-NATIVE-TUI.md).

## Plus and Pro: same display implementation

Continuum renders the usage windows Codex actually returns for the selected account/model. A five-hour and Weekly response gives two rows; Weekly alone gives one WEEKLY row. Unknown/blank data is not an invented plan limit or unlimited usage. Labels, remaining percentages and resets stay together in Full, Monitor and Micro. **There is no Pro-only patch or subscription-tier switch.** [Quota contract and evidence](docs/QUOTA-PRESENTATION.md).

## Open the latest recorded preview

BP211 includes both the accepted icon and quota correction. After following its download/extraction instructions, reopen it with PowerShell 7:

```powershell
$p=Join-Path $HOME 'Downloads\Continuum-BP211-QuotaFix\Unpacked\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe'
if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw 'BP211 not found; use the source build instructions below.'}
Start-Process -FilePath $p -WorkingDirectory (Split-Path -Parent $p)
```

The path is literal and version-specific; merging source/docs does not update an installed EXE. Keep its DLLs, `data`, bridge and workers beside it. Opening the app can query Codex metadata/usage but does not schedule a model turn. [Artifact/run/hash and expiry](docs/CURRENT-STATE.md).

**Download distinction:** [v1.11.0](https://github.com/Dukxud/codex-resume-scheduler/releases/tag/v1.11.0), still the latest published release at closeout, is the **older WinForms ZIP**, not current Flutter Continuum. CI previews are unsigned and expire. No new public production release is authorized during the pause.

## Build from source when needed

Runtime prerequisites: Windows x64 and signed-in desktop, PowerShell 7 in its standard installation, Node, Git and npm Codex installed/signed in. Building additionally needs Flutter and Visual Studio's Desktop development with C++ workload. The pinned CI baseline uses Flutter 3.47.9, Node 22 and Windows 2022; this is build evidence, not a promise every future CLI/SDK version is compatible.

From PowerShell 7, with `flutter.bat` on PATH:

```powershell
$ErrorActionPreference='Stop'
$repo=Join-Path $HOME 'source\continuum'
if(Test-Path -LiteralPath $repo){throw 'Checkout already exists; inspect it before updating, or choose another path.'}
git clone --branch main --single-branch https://github.com/Dukxud/codex-resume-scheduler.git $repo
if($LASTEXITCODE -ne 0){throw 'Clone failed'}
Set-Location -LiteralPath $repo
pwsh -NoProfile -STA -File .\flutter_port\Build-WindowsPreview.ps1 -OutputDirectory "$HOME\Downloads\Continuum-Main"
if($LASTEXITCODE -ne 0){throw 'Build failed; no preview launched'}
$p=Join-Path $HOME 'Downloads\Continuum-Main\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe'
if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw 'Built executable missing'}
Start-Process -FilePath $p -WorkingDirectory (Split-Path -Parent $p)
```

The builder refuses existing output packages; choose a fresh output directory for a new build. A source clone alone is not a compiled preview. [Developer commands](flutter_port/README.md).

## Documentation and evidence

[Documentation index](docs/README.md) · [User guide](docs/USER-GUIDE.md) · [Architecture](docs/ARCHITECTURE.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) · [Security](docs/SECURITY-AND-PRIVACY.md) · [Windows acceptance](docs/CONTINUUM-WINDOWS-ACCEPTANCE.md) · [Screenshots](docs/SCREENSHOTS.md) · [Contributing](docs/CONTRIBUTING.md) · [Release policy](docs/RELEASE-POLICY.md).

BP210's title-bar icon was visually accepted. BP211 passed Windows CI and all 47 package checksums; its live quota-display screenshot was not provided before pause. Original Shared task completion passed but exposed a disconnect defect; the fixed retained-terminal/dual-surface behavior still needs native acceptance. Merging at the owner's direction does not manufacture those missing results. Historical screenshots and reviews remain explicitly historical.

Closing the GUI or pausing project development **does not cancel scheduled Windows tasks**. Do not disable antivirus, run unrestricted access, execute Codex, publish or expand scope as a side effect of this handoff. [MIT license](LICENSE).
