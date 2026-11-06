# Continuum — Flutter Windows developer guide

**Current:** merged into `main` on 6 Nov 2026 (Flutter foundation PR #17, Shared sessions PR #18). This is a **Windows Flutter unsigned engineering preview**, not a production release. The [public Release](https://github.com/Dukxud/codex-resume-scheduler/releases/latest) remains the older WinForms version. Read [root README](../README.md) before using instructions from historical v1.16 audits.

## What Flutter includes

- Current **Continuum** desktop design with Full / Monitor / Micro views and optional Always on Top; Flutter FragmentProgram version of the approved Aero optical palette, animated usage/countdown surfaces, and an Appearance editor with **Colors** and **Optics** tabs. Changes preview and persist without an extra Save action.
- The Windows **JSON bridge** delegates persisted scheduling and quota reads to the existing PowerShell/Node runtime and a pinned worker.
- Three new-job execution modes: **Background** (noninteractive, optional bounded quota-only continuation), **Native terminal** (ordinary Codex CLI TUI), and **Shared session** (one App Server owner, Continuum live panel, optional original Codex TUI attached as a client). The default is Native terminal, but previously saved draft choices can be restored.
- Schedules validate the current conversation, Git root, branch, workspace, model catalog, effort and access. A UI build is not proof the backend has capacity to run a turn.

See [User guide](../docs/USER-GUIDE.md), [Shared TUI lifecycle](../docs/SHARED-NATIVE-TUI.md), [architecture](../docs/ARCHITECTURE.md), and [native acceptance checklist](../docs/CONTINUUM-WINDOWS-ACCEPTANCE.md).

## Requirements

**To run a prebuilt unsigned preview:** Windows 10/11 x64, signed-in desktop, PowerShell 7 (standard install path), Node.js, Git, npm Codex CLI installed and signed in; keep the **entire package** together.

**To build:** all of the above plus Flutter stable 3.47+ (or a version known to compile the checkout) and Visual Studio **Desktop development with C++** tools. Ensure `flutter.bat` resolves on `PATH`.

## Run from source (tests then debug GUI)

```powershell
git clone --branch main --single-branch https://github.com/Dukxud/codex-resume-scheduler.git "$HOME\source\continuum"
cd "$HOME\source\continuum"
pwsh -NoProfile -STA -File .\flutter_port\Run-WindowsReview.ps1
```

This executes source/bridge integrity checks, Flutter setup, analysis and tests **once**, then runs the Windows GUI. `-TestsOnly` skips the GUI. It does **not** start an actual Codex turn. A live Codex acceptance task always requires explicit operator authorization.

## Standalone unsigned review package

```powershell
pwsh -NoProfile -STA -File .\flutter_port\Build-WindowsPreview.ps1 -OutputDirectory "$HOME\Downloads\Continuum-Main"
& "$HOME\Downloads\Continuum-Main\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe"
```

The build outputs **both** `CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW.zip` and an extracted folder with the EXE, Flutter runtime, worker scripts/components and `SHA256SUMS.txt`. It builds/repackages and independently checks the ZIP contents. An existing destination causes a **fail-closed** error rather than overwriting a prior tested package. Use a unique output directory for each build.

**Do not treat the package as a signed installer or copy the executable alone.** The ZIP and README explicitly state it is an engineering preview.

## Execution ownership

| Mode | Engine | Interaction | Quota continuation |
| --- | --- | --- | --- |
| Background | Pinned scheduled `codex exec --json` worker | Saved event log/history | Off by default; quota-only, max three verified follow-ups |
| Native terminal | Native Codex TUI in Windows terminal | Questions/approvals in terminal | Disabled |
| Shared session | Single authenticated loopback App Server + named-pipe status | Continuum panel and optional native TUI client | Disabled |

A Shared session **cannot attach to an independently running Codex CLI process**. The GUI's native-attach button uses a remote client attached to the owner's saved thread ID; no second App Server or scheduled execution owner. A current native acceptance gate is still required for simultaneous approval behavior and for lifecycle handling after turn completion.

## Architecture and platform boundary

- Entry: `flutter_port/lib/main.dart`; activity panel `shared_session_panel.dart`; state/controller `scheduler_controller.dart`.
- JSON boundary: `flutter_port/windows_bridge.ps1`.
- Owner/client: `components/SharedCodexSession/{main,host,remote,client,protocol}.mjs`.
- Worker: `CodexRunEngine.ps1`; packaging: `flutter_port/Build-WindowsPreview.ps1`.
- Flutter UI and optical effects are portable in principle. **Scheduled workers on macOS, Linux and web are not implemented**, because the bridge currently depends on Windows Task Scheduler and Windows-specific runtime paths.

## Evidence and policy

The latest mock/Flutter Windows CI build passed on `6cd11c6` and its complete source tree matched merged main `15b32f74`. BP207 launched its unsigned preview on BLACK-PUDDLE. **Real retained native TUI attachment after the lifecycle fix, and dual-surface approvals/questions, remain unverified.** Do not silently upgrade these to accepted features based on mocks. Do not merge a later PR or publish a release without explicit authorization. See [release policy](../docs/RELEASE-POLICY.md).