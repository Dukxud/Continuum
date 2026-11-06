# Continuum — Codex Resume Scheduler

**Schedule an existing Codex conversation to resume later, monitor its activity, and optionally open its native terminal.** A Windows desktop utility powered by Windows Task Scheduler, built with Flutter.

**Status: open-source engineering preview, not a signed public release.** The current code lives on [main](https://github.com/Dukxud/codex-resume-scheduler/tree/main). This is an independent community project, **not an OpenAI product**.

> **Download distinction:** The [latest GitHub Release](https://github.com/Dukxud/codex-resume-scheduler/releases/latest) is the **older PowerShell/WinForms application (v1.11.0)**. It is **not** the current Continuum Flutter executable. For Continuum, build from \`main\` as shown below. Prebuilt CI artifacts are unsigned, short-lived engineering previews and must not be presented as signed installers.

## What you can do

- Resume a saved Codex CLI conversation at a chosen local time, in its Git checkout, with selected model, reasoning effort, and permissions.
- See model-specific usage windows and reset information from Codex's App Server. The app does **not** promise that a displayed reset means access is restored.
- Choose **Background**, **Native terminal**, or **Shared session** execution (see comparison below).
- Monitor scheduled jobs and inspect retained results; prevent competing *scheduler-owned* executions against the same Codex session.
- Use Full, Monitor, or Micro windows, optional Always on Top, and customizable Aero-inspired bars.
- Optionally allow bounded, verified **quota-only** continuation for new **Background** jobs. No general-purpose infinite retry loop.

## Screenshots

The [screenshot gallery and capture protocol](docs/SCREENSHOTS.md) includes **real Windows evidence**, explicitly tagged by build/date and outcome. The existing November 6 capture documents the **original shared-terminal lifecycle defect**, **not** an accepted release screenshot. Fresh, privacy-reviewed hero screenshots are still needed before marketing or a public release.

## Three execution modes

| Mode | Who owns execution? | What you see | On closing the terminal | Quota-only auto-continuation |
| --- | --- | --- | --- | --- |
| **Background** | Pinned scheduled noninteractive worker | Logs and saved results | Not applicable | **Optional**, off by default |
| **Native terminal** | Codex CLI in a real terminal | Real Codex TUI with native interaction | Native session ends; outcome is recorded as **Finished**, not proof of task success | No |
| **Shared session** | One scheduled Codex App Server | Continuum live panel **and** optional **Open Codex Terminal** TUI client | Detaches the viewer; execution owner can remain | No |

**Shared is not "attach to any Codex process".** It only attaches to shared sessions *started by Continuum*. If Codex is already running independently, do not attempt to have Continuum take over its active turn. The single-conversation safety boundary remains in effect. [Details and limitations](docs/SHARED-NATIVE-TUI.md).

The Shared owner retains the server after scheduled-turn completion while an attached terminal remains open, with a 15-second no-viewer idle grace and a two-hour maximum attachment lifetime. A GUI snapshot falls back to the persisted result after owner shutdown. This behavior has mock/CI coverage; signed-in Windows acceptance of the latest lifecycle fix and simultaneous approvals is **not yet complete**.

## Install and open the current Continuum preview (Windows)

**Requirements:** Windows 10/11 x64 and a signed-in desktop; [PowerShell 7](https://learn.microsoft.com/powershell/); [Node.js](https://nodejs.org/); [Git](https://git-scm.com/); [Codex CLI installed with npm](https://github.com/openai/codex) and signed in. **Building** also requires [Flutter stable](https://docs.flutter.dev/get-started/install/windows/desktop) and the Visual Studio **Desktop development with C++** workload. An installation of the Codex CLI does not confer any particular model access.

In PowerShell 7:

\`\`\`powershell
git clone --branch main --single-branch https://github.com/Dukxud/codex-resume-scheduler.git "$HOME\source\continuum"
cd "$HOME\source\continuum"
pwsh -NoProfile -STA -File .\flutter_port\Build-WindowsPreview.ps1 -OutputDirectory "$HOME\Downloads\Continuum-Main"
& "$HOME\Downloads\Continuum-Main\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe"
\`\`\`

**Exact executable after that build:** \`%USERPROFILE%\Downloads\Continuum-Main\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe\`. Keep the accompanying \`data\`, DLLs, worker modules, and scripts beside it. Do **not** move the EXE by itself. The build refuses to overwrite an existing review package; choose another output directory when rebuilding.

For a one-command **source-level development review** (tests then desktop launch), see [Flutter development instructions](flutter_port/README.md). To review CI binaries, download the artifact for the **exact tested commit** from [GitHub Actions](https://github.com/Dukxud/codex-resume-scheduler/actions); artifacts expire and are **not** an official release.

## First scheduled run

1. Sign in to Codex CLI and ensure a saved conversation exists. Launch Continuum.
2. Choose the **conversation**, verify the detected **Git repository**, and select the model, effort and access.
3. Set the date and time, enter a concrete instruction, and choose an **execution mode**.
4. Click **Schedule once**. Windows must be awake, online, and signed in when the job is due.
5. For **Shared session**, open its running card and click **Open Codex Terminal** to attach a real TUI client. For **Native terminal**, Codex opens its own console.

**Safety:** Start with a disposable conversation and **Read-only** access. Never use unrestricted/YOLO access on untrusted work. A registered Windows task is not evidence that Codex completed its turn. [User guide](docs/USER-GUIDE.md) · [Security](docs/SECURITY-AND-PRIVACY.md) · [Troubleshooting](docs/TROUBLESHOOTING.md).

## Documentation

| Read this | Purpose |
| --- | --- |
| [Documentation index](docs/README.md) | Navigation, scope, historical references |
| [User guide](docs/USER-GUIDE.md) | Scheduling, modes, monitoring, windows, quota and history |
| [Shared session implementation](docs/SHARED-NATIVE-TUI.md) | Owner/viewer lifecycle, authority, limits and remaining acceptance |
| [Architecture](docs/ARCHITECTURE.md) | Current Flutter/bridge/worker shape and legacy PowerShell modules |
| [Windows acceptance](docs/CONTINUUM-WINDOWS-ACCEPTANCE.md) | Native test gate and exact expected behavior |
| [Screenshots](docs/SCREENSHOTS.md) | Real evidence and capture checklist |
| [Release policy](docs/RELEASE-POLICY.md) | Preview vs signed distribution |
| [Contributing](docs/CONTRIBUTING.md) | Safe local tests and PR expectations |
| [Reusable components](components/README.md) | Separately imported PowerShell modules |
| [Older WinForms README](docs/LEGACY-WINFORMS-README.md) | Preserved historical documentation only |

## Developer verification

\`\`\`powershell
node --test tests/shared-codex-session.test.mjs tests/shared-codex-remote.test.mjs
pwsh -NoProfile -File .\tests\flutter-port-source.test.ps1
pwsh -NoProfile -STA -File .\tests\flutter-port-bridge.test.ps1
pwsh -NoProfile -STA -File .\flutter_port\Run-WindowsReview.ps1 -TestsOnly
\`\`\`

These checks verify protocol mocks, source, bridge, and Flutter tests. **They do not prove live Codex TUI attachment or target-machine acceptance.** Do not run live Codex integration tests without the operator's explicit authorization. The main branch was formed by merging [#17](https://github.com/Dukxud/codex-resume-scheduler/pull/17) and [#18](https://github.com/Dukxud/codex-resume-scheduler/pull/18) on November 6, 2026. The exact merge baseline was \`15b32f74b0ea243e1e0bfa833ff33aa073c59089\`.

## Public availability and feedback

This is a **public source repository**, not a polished installer. The current Flutter build requires a development toolchain or manual handling of an expiring unsigned CI artifact. [Report reproducible bugs or request features via GitHub Issues](https://github.com/Dukxud/codex-resume-scheduler/issues). Attach a sanitized screenshot, Windows version, exact commit, execution mode and observed result; **never** publish tokens, full terminal transcripts, repository secrets or session IDs.

**License:** [MIT](LICENSE).
