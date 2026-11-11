# Release and preview policy

Continuum's Flutter application is an unsigned Windows engineering preview. The owner authorized publication of the first public engineering preview on 11 November 2026. Feature expansion, live Codex testing, and signed production publication remain paused. [Current state](CURRENT-STATE.md) records builds and outstanding verification.

## Available builds

- [Continuum 0.1.0 Preview 1](https://github.com/Dukxud/Continuum/releases/tag/v0.1.0-preview.1) provides the current Flutter Windows x64 ZIP and a SHA-256 checksum. It is an unsigned prerelease for evaluation.
- [v1.11.0](https://github.com/Dukxud/Continuum/releases/tag/v1.11.0) is the older WinForms application.
- The [PR #24 preview record](CURRENT-STATE.md#source-layout-preview--11-nov-2026) links the earlier verified Flutter package, source SHA, checksums, download command, and expiry. That build predates the current desktop relocation. CI artifacts are temporary review downloads.
- [Getting started](GETTING-STARTED.md) provides the durable source-build path. Existing installations are not updated by source merges.

## Preview packaging

`src/desktop/Build-WindowsPreview.ps1` builds and verifies a complete release-mode folder and ZIP. It installs the checked-in icon after runner generation and includes the backend, bridge, required components, Flutter runtime, license, `build-info.json`, and checksum manifest. The archive name derives from the Flutter version in `src/desktop/pubspec.yaml`; dependency locks are enforced. Existing package destinations are preserved. Prevalidated-package mode is restricted to GitHub Actions.

The unified [CI workflow](../.github/workflows/ci.yml) runs source, documentation, and protocol checks for pull requests and pushes to `main`. Application changes also run the full Windows suite, compile the release app, verify its package, and upload a temporary unsigned preview. Documentation-only changes skip Windows compilation. CI does not publish GitHub releases.

Package hashes establish content integrity. Publisher authenticity, native application behavior, and signing require separate verification. Unsigned previews do not require broad antivirus or SmartScreen exclusions.

## Production release requirements

Publication requires maintainer authorization and completion of the following:

1. Set the intended release version in `src/desktop/pubspec.yaml` and verify it in the archive name and build metadata. The separate `legacy/winforms/VERSION` applies only to retained WinForms/component packages.
2. Complete the outstanding [native acceptance scenarios](CONTINUUM-WINDOWS-ACCEPTANCE.md).
3. Sign and timestamp distributed executables and verify their signatures; complete antivirus review.
4. Provide release notes, complete downloadable artifacts, checksums, and a rollback plan.
5. Use current, accurately captioned [product screenshots](SCREENSHOTS.md).

The [historical readiness assessment](history/DISTRIBUTION-READINESS.md) retains earlier findings. Build and package checks alone do not close these release requirements.
