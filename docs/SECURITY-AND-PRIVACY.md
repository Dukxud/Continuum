# Continuum security and privacy

## Trust model

Continuum is a locally running Windows Flutter interface over a PowerShell JSON bridge, scheduled pinned worker, and your already installed npm Codex CLI. **There is no Continuum cloud account or telemetry service in this repository.** Codex itself communicates with OpenAI according to its own account and configuration; Continuum does not mean "offline Codex."

- Job settings and instruction text are written under `%LOCALAPPDATA%\CodexResumeScheduler`; **do not put secrets in prompts, paths or issue screenshots**.
- Scheduled workers use immutable SHA-256-verified runtime snapshots; hashes detect unexpected file changes but **are not code-signing or protection from a malicious Windows account owner**.
- The scheduler prevents duplicate **scheduler-owned** writers using a per-conversation Windows mutex. It cannot reliably detect or take over every separate interactive Codex process.
- Workspace/account identity and model availability are verified before unattended execution; missing or contradictory evidence blocks execution.
- **Read-only** limits intended write access; **Workspace-write** allows changes within the configured sandbox; **YOLO** disables sandboxing and approvals, potentially affecting files outside the checkout. Use a disposable Git repository for initial tests.

## Shared native terminal

The Shared host starts a single App Server bound to `127.0.0.1`. The connection uses a random capability token; a SHA-256 verifier is supplied to the server. Continuum's named-pipe protocol requires its own per-job secret. Native TUI credentials are sent only over the authenticated named-pipe connection, not written into public status snapshots or CLI arguments. Secrets can still be accessible to sufficiently privileged local processes.

A native TUI is a **client of the existing owner**, not a second executor. It does not grant an independent unattended permission mode or a way to bypass Codex approval policy. Authorization and approval-handling behavior must be validated against the installed Codex version, not merely inferred from mocks.

The server remains available while a TUI lease is attached (max two hours after scheduled-turn completion). No viewer triggers 15 seconds of grace. This is bounded housekeeping, **not** a promise of indefinite background uptime.

## Binary provenance

- Current Continuum Flutter packages are **unsigned engineering previews**. A SHA-256 manifest checks content integrity **only**. It does not authenticate the publisher.
- The latest published release currently corresponds to **legacy v1.11.0 WinForms**, not the merged Flutter baseline.
- Do not recommend disabling antivirus or making broad exclusions to install a preview.
- A public production build needs authorized code signing, timestamping, antivirus/SmartScreen review, native QA and a release process. [Release policy](RELEASE-POLICY.md).
- The WebView2 and WPF security discussions in [historical security review](SECURITY-REVIEW.md) apply to the legacy renderer; the Flutter port uses its own assets/shader and Windows bridge.

## Reporting security issues

Avoid uploading `auth.json`, raw Codex session IDs, full transcripts, personal local paths or secrets. Provide a sanitized sample and the pinned commit. Use GitHub repository issue channels for nonsensitive bugs; do not include exploit details that would expose another user.