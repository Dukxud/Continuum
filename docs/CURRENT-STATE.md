# Current state and pause handoff

**Status: paused at the owner's request, 6 Nov 2026 (America/Chicago).** No feature expansion, live Codex testing, release publication, or automatic follow-up is authorized by this pause. The repository remains usable; this does not archive GitHub or cancel existing Windows tasks.

## Repository maintenance — 11 Nov 2026

The owner authorized a repository presentation and source-organization cleanup. [PR #23](https://github.com/Dukxud/codex-resume-scheduler/pull/23) refreshed the landing page and organized documentation. [PR #24](https://github.com/Dukxud/codex-resume-scheduler/pull/24) merged the source layout at `f72617dd1bbb50722e22780c6f77e740f6d5eae3`, separating active workers and readers under `src/backend/` from the original frontend under `legacy/winforms/`. The worker entry point is `src/backend/Invoke-CodexJob.ps1`; package and snapshot manifests retain the same nested layout. Existing installed previews and scheduled runtime copies are not moved or rewritten by this source change. Feature development and production releases remain paused.

## Source-layout preview — 11 Nov 2026

This is the most recent verified application package recorded here. It includes the source-layout cleanup as well as the earlier icon and quota corrections. The older BP211 record below preserves the preview available at the 6 Nov pause.

| Item | Recorded result |
| --- | --- |
| Built source | `e998e489af688567081209f6b30a18459fd0cb1e`; the PR #24 merge has the same source tree |
| Local automated checks | 76 Node tests, 40 PowerShell test files, and 104 Flutter tests passed; Flutter analysis had no errors or warnings |
| Hosted Windows verification | [Run 43091625553](https://github.com/Dukxud/codex-resume-scheduler/actions/runs/43091625553) passed source/bridge/worker checks, Flutter analysis/tests, debug and release compilation, native icon checks, and packaging |
| Downloaded package | All 47 manifest entries independently verified; packaged bridge and runtime snapshot checks passed outside the source checkout with an isolated profile |
| Native acceptance | No new live Codex task or product GUI acceptance was performed for the source-layout change; the open scenarios below remain pending |

The [unsigned Windows artifact](https://github.com/Dukxud/codex-resume-scheduler/actions/runs/43091625553/artifacts/13888139672) is named `flutter-windows-unsigned-e998e489af688567081209f6b30a18459fd0cb1e` (ID `13888139672`). Its recorded expiry is **18 Nov 2026, 20:01 UTC**. The GitHub artifact archive SHA-256 is `9ae45761a5255a99cb7cba72db20ae08d61c2830429148d8b1db3d3ff7020943`; the inner application ZIP SHA-256 is `bb388608d7d9ed2e8e652616ff60046d1a87529a4c89a235d7bc1ab626f9f70e`.

Until expiry, download with an authenticated GitHub CLI from PowerShell 7. This verifies and extracts the package without launching it:

```powershell
$ErrorActionPreference = 'Stop'
$continuumDownload = Join-Path $HOME 'Downloads\Continuum-SourceLayout-PR24'
if (Test-Path -LiteralPath $continuumDownload) {
    throw 'Download directory already exists. Choose a fresh path or use the existing verified package.'
}
gh run download 43091625553 -R Dukxud/codex-resume-scheduler `
    -n flutter-windows-unsigned-e998e489af688567081209f6b30a18459fd0cb1e `
    -D $continuumDownload
if ($LASTEXITCODE -ne 0) { throw 'Download failed. Check GitHub authentication and artifact expiry.' }
$continuumArchive = Join-Path $continuumDownload 'CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW.zip'
if ((Get-FileHash -LiteralPath $continuumArchive -Algorithm SHA256).Hash -ne 'bb388608d7d9ed2e8e652616ff60046d1a87529a4c89a235d7bc1ab626f9f70e') {
    throw 'Preview ZIP checksum mismatch.'
}
Expand-Archive -LiteralPath $continuumArchive -DestinationPath (Join-Path $continuumDownload 'Unpacked')
```

The exact executable path is:

```text
%USERPROFILE%\Downloads\Continuum-SourceLayout-PR24\Unpacked\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe
```

To open the extracted app:

```powershell
$continuumExe = Join-Path $HOME 'Downloads\Continuum-SourceLayout-PR24\Unpacked\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe'
if (!(Test-Path -LiteralPath $continuumExe -PathType Leaf)) { throw 'Extracted executable not found.' }
Start-Process -FilePath $continuumExe -WorkingDirectory (Split-Path -Parent $continuumExe)
```

Keep the complete package together. Startup can query Codex metadata and usage; it does not schedule a job. After the artifact expires, use [Getting started](GETTING-STARTED.md) to build from source. The local review encountered Flutter's Windows symlink prerequisite; [troubleshooting](TROUBLESHOOTING.md#build-prerequisites) covers that setup error.

## Resume here

Read this file first, then [the user guide](USER-GUIDE.md), [architecture](ARCHITECTURE.md), [quota presentation](QUOTA-PRESENTATION.md), and [Windows acceptance](CONTINUUM-WINDOWS-ACCEPTANCE.md). Current source authority is `main`; dated historical reviews are not instructions to reopen or re-merge earlier PRs.

## Baseline and evidence at the 6 Nov pause

| Item | Recorded state |
| --- | --- |
| Flutter foundation / Shared sessions | PRs #17 and #18 merged; original combined baseline `15b32f74b0ea243e1e0bfa833ff33aa073c59089` |
| Native Windows icon | PR #21 merged at `fa812e3c2f294c1b0e3f9ff39ef8bdb3c77b8210`; BP210 screenshot on BLACK-PUDDLE confirms the Continuum title-bar icon in Micro, not a warning triangle |
| Quota display | PR #22 merged at `f83b11bc3acb9f0447b41d0a7b7d414bd86364ff`; no subscription-tier condition; Full, Monitor and Micro display actual returned windows |
| Application preview at pause | BP211, built from `796f25e757412a8cabc3fa68531405ffc1b6a21b`; its source tree equals the quota merge tree |
| Windows verification | [Run 42327638037](https://github.com/Dukxud/codex-resume-scheduler/actions/runs/42327638037) passed source/worker/bridge checks, Flutter analysis/tests, debug and release builds, icon verification and package integrity |
| Documentation | PR #19 brings current onboarding, historical separation and this pause handoff into the baseline; documentation commits do not create a new executable |
| Public release | [v1.11.0](https://github.com/Dukxud/codex-resume-scheduler/releases/tag/v1.11.0) is still the legacy WinForms release. No signed Continuum production release was published |

BP numbers identify review steps/packages, not product version numbers. `VERSION`, Flutter package metadata and the preview folder label still use different development-era version identifiers; publishing must reconcile them rather than invent a new version here.

## Historical BP211 executable and reproducibility

The earlier BP211 package used this extraction path:

```text
%USERPROFILE%\Downloads\Continuum-BP211-QuotaFix\Unpacked\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe
```

Reopen it in PowerShell 7 (no build and no task scheduled):

```powershell
$p=Join-Path $HOME 'Downloads\Continuum-BP211-QuotaFix\Unpacked\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe'
if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw 'BP211 is not installed at the documented path; use the build instructions.'}
Start-Process -FilePath $p -WorkingDirectory (Split-Path -Parent $p)
```

The app can perform read-only Codex metadata/usage queries on startup. Opening it is not starting a model turn.

Build artifact: `flutter-windows-unsigned-796f25e757412a8cabc3fa68531405ffc1b6a21b`, artifact ID `13555632717`, run `42327638037`. Its recorded expiry is **14 Nov 2026, 02:13 UTC**; an artifact link is not permanent distribution. The inner `CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW.zip` SHA-256 is `85a540f1366ee4780432cc8d831d532661e91b4bd1647b53b1b6e917e30e7d5b`; all **47** manifest entries were independently checked during closeout. Keep the entire extracted package, not only its EXE. After expiry, build from source using [the Flutter guide](../flutter_port/README.md).

## What is settled

- Background, Native terminal and Shared session are distinct execution modes; existing independently running Codex terminals are **not** attachable by this version.
- Plus and Pro use the same quota presentation. One returned Weekly window means one WEEKLY row; a five-hour plus Weekly response means two correctly labeled rows. No tier-specific schedule or permission rules were added.
- The Windows icon correction is merged and visually observed. The identical earlier extracted icon hashes did not establish the cause of the original title-bar substitution; do not claim that root cause was proven.
- Scheduling retains pinned runtime, repository/branch, workspace/model, permissions and per-conversation ownership checks. Presentation changes did not alter them.

## Deferred work — not acceptance claims

1. **BP211 live display:** automated cases pass, but no post-fix live screenshot was supplied before the pause. Owner authorization to merge is not a screenshot or native test result.
2. **Shared lifetime:** the initial disposable turn completed but the original owner shutdown disconnected the TUI. The 15-second no-viewer grace/two-hour retention fix is merged and mock-tested; repeat real retained-terminal acceptance remains pending.
3. **Questions and multi-turn use:** dual-surface approval/question handling and later TUI turns need live verification. The current host stops processing App Server events after the scheduled turn is completed (`onAppMessage` returns when `completed`); the retained terminal does not establish ongoing GUI mirroring or approval forwarding. The two-hour cap is not guaranteed to wait for a later active turn.
4. **Distribution:** clean current screenshots, consistent versioning, signing, antivirus review and an authorized release remain deferred. Historical BP204 captures are defect evidence, not current hero screenshots.
5. **PR #20:** older alternative icon implementation, superseded in practice by accepted/merged #21. Do not merge it as part of resuming; the branch/review record is retained pending explicit disposition.

## When development resumes

Fetch `main` and read this handoff before planning. Inspect open PRs and current compatibility instead of assuming old artifacts still exist. Use mocks and bounded test runs first. Any live Codex task requires explicit operator authorization; any merge or release requires explicit authorization. Recheck the deferred acceptance items before expanding scope. Every reviewable Windows build must include a copy-paste launch/download command and exact executable path. Do not make the owner search for artifacts.
