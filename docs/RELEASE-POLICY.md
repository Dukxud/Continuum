# Release and preview policy

Continuum's Flutter application is an unsigned Windows engineering preview. Feature development and production publication are paused; repository maintenance continues within the owner's authorized scope. [Current state](CURRENT-STATE.md) records builds and outstanding verification.

## Available builds

- The latest public release checked on 11 Nov 2026 is [v1.11.0](https://github.com/Dukxud/codex-resume-scheduler/releases/tag/v1.11.0), the older WinForms application.
- The [PR #24 preview record](CURRENT-STATE.md#source-layout-preview--11-nov-2026) identifies the verified Flutter package, source SHA, checksums, download command, and expiry. CI artifacts are temporary review downloads.
- [Getting started](GETTING-STARTED.md) provides the durable source-build path. Existing installations are not updated by source merges.

## Preview packaging

`flutter_port/Build-WindowsPreview.ps1` builds and verifies a complete release-mode folder and ZIP. It installs the checked-in icon after runner generation and includes the backend, bridge, required components, Flutter runtime, and checksum manifest. Existing package destinations are preserved. Prevalidated-package mode is restricted to GitHub Actions.

The Flutter preflight workflow runs for matching pull requests to `main`. Shared protocol checks have separate feature-branch and manual triggers. A push to `main` does not automatically produce a new executable or publish a release.

Package hashes establish content integrity. Publisher authenticity, native application behavior, and signing require separate verification. Unsigned previews do not require broad antivirus or SmartScreen exclusions.

## Production release requirements

Publication requires maintainer authorization and completion of the following:

1. Reconcile `VERSION`, Flutter package metadata, and archive labels into one release version.
2. Complete the outstanding [native acceptance scenarios](CONTINUUM-WINDOWS-ACCEPTANCE.md).
3. Sign and timestamp distributed executables and verify their signatures; complete antivirus review.
4. Provide release notes, complete downloadable artifacts, checksums, and a rollback plan.
5. Use current, accurately captioned [product screenshots](SCREENSHOTS.md).

The [historical readiness assessment](history/DISTRIBUTION-READINESS.md) retains earlier findings. Build and package checks alone do not close these release requirements.
