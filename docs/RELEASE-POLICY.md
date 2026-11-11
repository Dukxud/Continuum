# Release and preview policy

**Paused on 6 Nov 2026.** The owner authorized the quota merge and documentation closeout, not public publication. [CURRENT-STATE.md](CURRENT-STATE.md) records the exact baseline.

- The latest published release checked at closeout is [v1.11.0](https://github.com/Dukxud/codex-resume-scheduler/releases/tag/v1.11.0), the older WinForms ZIP. It is not the current Flutter Continuum executable.
- BP211 is the latest recorded unsigned application preview. Its Windows checks passed, but a preview archive, source merge, icon and checksum manifest do not establish publisher authenticity or every native test.
- `.github/workflows/flutter-port-preflight.yml` runs for matching pull requests to `main`; the Shared protocol workflow has its own feature-branch push/manual triggers. An arbitrary `main` push is not a promise of a fresh executable. No workflow activity here is permission to publish a release.
- `Build-WindowsPreview.ps1` builds/verifies a complete Flutter release-mode ZIP/folder, installs the pinned icon after runner generation, preserves worker files, and refuses existing destinations. CI prevalidated-package mode is restricted to Actions.
- Artifact retention is finite. BP211's recorded artifact expiry is 14 Nov 2026 at 02:13 UTC. Source/build instructions must remain usable after a preview link expires. Do not repurpose the historical release as a download for the current app.
- Production publication requires renewed owner authorization, consistent version numbers, trusted signing/timestamping, signature checks, antivirus review, native acceptance, release notes, accessible complete artifacts and a rollback plan. Current `VERSION`, pubspec and folder labels are development identifiers, not a new public release.
- Never disable antivirus/SmartScreen globally or create broad exclusions to make an unsigned preview run. SHA-256 checks prove content integrity, not trust in a publisher.
- Screenshots must show real, accurately captioned behavior. Historical failures and pre-quota-fix images cannot advertise BP211 success. [Screenshot rules](SCREENSHOTS.md).

Distribution work and promotion are deferred. [Readiness assessment](history/DISTRIBUTION-READINESS.md) is a recorded backlog, not an active launch instruction.
