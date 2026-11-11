# Current project state

Continuum is an unsigned Windows engineering preview. Repository maintenance is active; feature expansion, live Codex testing, and production publication remain paused.

## Source baseline

The active application is organized under `src/desktop/` and `src/backend/`. Reusable PowerShell modules and the Shared session host live in `components/`; the original WinForms interface is retained in `legacy/winforms/`. See [architecture](ARCHITECTURE.md) for ownership boundaries and [testing](../tests/README.md) for verification commands.

| Area | State |
| --- | --- |
| Flutter interface | Full, Monitor, Micro, history, appearance, and pinning are implemented |
| Execution | Background, native terminal, and Shared modes are implemented |
| Quota display | Uses actual returned windows; latest live account display still needs native verification |
| Shared lifecycle | Retention is implemented; retained-terminal and approval scenarios remain pending |
| Windows branding | Checked-in icon is installed after runner generation; earlier Micro title-bar observation is recorded |
| Distribution | Unsigned source builds and temporary CI previews; no signed production Continuum release |

[Windows acceptance](CONTINUUM-WINDOWS-ACCEPTANCE.md) distinguishes automated checks from native observations. [Shared session limits](SHARED-NATIVE-TUI.md) include incomplete mirroring of later terminal turns. Closing the application does not cancel registered tasks.

## Build identity

The Flutter version is `0.1.0+1` in `src/desktop/pubspec.yaml`. New preview names derive from it and include `build-info.json` with the source commit and build time. Use the source SHA and package checksum to identify a particular preview. The WinForms version in `legacy/winforms/VERSION` belongs to the retained application.

The public [v1.11.0 release](https://github.com/Dukxud/codex-resume-scheduler/releases/tag/v1.11.0) is the older WinForms application. Source merges do not replace installed executables. Follow [Getting started](GETTING-STARTED.md) for a fresh source build and [release policy](RELEASE-POLICY.md) for publication requirements.

### Source-layout preview — 11 Nov 2026

[PR #24](https://github.com/Dukxud/codex-resume-scheduler/pull/24) produced a verified earlier preview at source `e998e489af688567081209f6b30a18459fd0cb1e`. It predates the desktop relocation and module extractions now in source. Its Windows build, 47 package-manifest checks, and extracted bridge checks passed.

The [pinned build record](https://github.com/Dukxud/codex-resume-scheduler/blob/060683a879ee8b876e34b69b7404bab1ec9298a9/docs/CURRENT-STATE.md) retains the exact download command, artifact and package hashes, executable path, and older BP211 evidence. Artifact `13888139672` expires on **18 Nov 2026 at 20:01 UTC**; historical archive names remain unchanged.

## Remaining acceptance

- Verify the latest quota display against a live account in all three views.
- Exercise retained Shared terminals, approval routing, server loss, and later-turn/cap-expiry behavior.
- Complete signing, publisher verification, release notes, and product captures before a production release.

The [acceptance ledger](CONTINUUM-WINDOWS-ACCEPTANCE.md) is the checklist. Dated reviews and original designs are retained in [project history](history/README.md). The original icon draft, PR #20, was superseded by merged PR #21.
