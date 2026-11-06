# Release and preview policy (current, 6 Nov 2026)

- **No production Flutter release has been published.** The [latest public GitHub Release](https://github.com/Dukxud/codex-resume-scheduler/releases/latest) is earlier **v1.11.0 WinForms ZIP**. It is **not** the Flutter Continuum EXE.
- Flutter verification CI can run on pushes; its artifacts are **short-lived, unsigned engineering previews**. **CI execution is not release publication.** Production publishing is disabled/manual until explicit approval and signing.
- `flutter_port/Build-WindowsPreview.ps1` outputs a Windows Flutter ZIP/folder with pinned worker sources, runtime and SHA-256 manifest. The builder refuses to overwrite an existing preview. Legacy PowerShell WinForms packaging scripts remain for earlier generations.
- SHA-256 manifests check file integrity; **they are not a publisher signature**.
- A production release requires explicit authorization, trusted code signing, timestamping, signature validation, direct Windows acceptance (including Shared TUI retention and approvals), antivirus/SmartScreen checks, compatibility notes and rollback plan.
- Do **not** disable antivirus, Bitdefender or SmartScreen globally or make broad exclusions to run a preview.
- Publish **only real, privacy-reviewed screenshots** with accurate build/outcome captions. Historical defect screenshots must never be presented as current passing behavior. See [SCREENSHOTS.md](SCREENSHOTS.md).
- [Distribution and adoption](DISTRIBUTION-READINESS.md) records why a public repository and legacy release are not equivalent to an accessible current installer.
- Reusable-component consumers retain their own acceptance. The SettingsStore module is not suitable as a durable transactional measurements database.
