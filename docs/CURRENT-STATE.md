# Current state and pause handoff

**Status: paused at the owner's request, 6 Nov 2026 (America/Chicago).** No feature expansion, live Codex testing, release publication, or automatic follow-up is authorized by this pause. The repository remains usable; this does not archive GitHub or cancel existing Windows tasks.

## Resume here

Read this file first, then [the user guide](USER-GUIDE.md), [architecture](ARCHITECTURE.md), [quota presentation](QUOTA-PRESENTATION.md), and [Windows acceptance](CONTINUUM-WINDOWS-ACCEPTANCE.md). Current source authority is `main`; dated historical reviews are not instructions to reopen or re-merge earlier PRs.

## Baseline and evidence

| Item | Recorded state |
| --- | --- |
| Flutter foundation / Shared sessions | PRs #17 and #18 merged; original combined baseline `15b32f74b0ea243e1e0bfa833ff33aa073c59089` |
| Native Windows icon | PR #21 merged at `fa812e3c2f294c1b0e3f9ff39ef8bdb3c77b8210`; BP210 screenshot on BLACK-PUDDLE confirms the Continuum title-bar icon in Micro, not a warning triangle |
| Quota display | PR #22 merged at `f83b11bc3acb9f0447b41d0a7b7d414bd86364ff`; no subscription-tier condition; Full, Monitor and Micro display actual returned windows |
| Latest application preview | BP211, built from `796f25e757412a8cabc3fa68531405ffc1b6a21b`; its source tree equals the quota merge tree |
| Windows verification | [Run 42327638037](https://github.com/Dukxud/codex-resume-scheduler/actions/runs/42327638037) passed source/worker/bridge checks, Flutter analysis/tests, debug and release builds, icon verification and package integrity |
| Documentation | PR #19 brings current onboarding, historical separation and this pause handoff into the baseline; documentation commits do not create a new executable |
| Public release | [v1.11.0](https://github.com/Dukxud/codex-resume-scheduler/releases/tag/v1.11.0) is still the legacy WinForms release. No signed Continuum production release was published |

BP numbers identify review steps/packages, not product version numbers. `VERSION`, Flutter package metadata and the preview folder label still use different development-era version identifiers; publishing must reconcile them rather than invent a new version here.

## Exact executable and reproducibility

After the BP211 download/extraction command, the existing Windows executable is:

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
