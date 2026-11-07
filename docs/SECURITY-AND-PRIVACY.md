# Security and privacy

**Scope:** current Windows Flutter preview, including Shared sessions, pinned icon and reported quota windows. Development is paused; see [CURRENT-STATE.md](CURRENT-STATE.md). Historical WinForms analysis remains in [SECURITY-REVIEW.md](SECURITY-REVIEW.md).

## Local trust and execution

Flutter delegates to the PowerShell JSON bridge and pinned scheduled worker. Codex uses the operator's installed CLI/account; a local scheduler does not make Codex offline. The application does not introduce a hosted Continuum account or an adoption telemetry service.

Job instructions/preferences/results and runtime snapshots live under `%LOCALAPPDATA%\CodexResumeScheduler`; job JSON identifies transcript paths. These files may contain private prompts, paths or command output. Runtime SHA-256 checks detect changes but are not publisher signatures or protection against the same Windows user deliberately modifying both metadata and files.

The worker verifies workspace identity, repository/branch, model/effort, quota and a per-conversation scheduler mutex. The mutex cannot detect/control every unrelated CLI instance. Do not schedule a thread already actively owned elsewhere. Read-only/workspace-write/unrestricted modes retain their actual Codex permission boundaries; unrestricted/YOLO can affect files outside the checkout and must never be used merely to bypass a failing test.

## Shared credentials and lifecycle

The server binds to loopback with a random capability token; only its SHA-256 verifier goes into server arguments. Raw token transfer uses the authenticated named pipe and native child's environment, not public snapshots. The pipe has its own secret in the transient `.shared.json` descriptor. Do not publish that file. Local privileged processes may still access credentials.

Supported approval methods and thread/turn identity are checked. Mock rejection tests are not proof that concurrent native/GUI questions and approvals work in practice. Post-completion retention applies to successful scheduled turns, with 15-second no-viewer grace and a two-hour cap; it is not an indefinite daemon. The host stops event processing after first completion, so later-turn mirroring/approval behavior and timeout during later work need separate review.

## Quota and binary presentation are not permissions

PR #22 renders actual returned windows for either Plus or Pro. It does not alter authorization, model access, sandbox, quota checks or retries, and must not be used to infer unlimited usage. PR #21's branded icon is a visual identity, not a certificate or antivirus verdict.

## Distribution/reporting

The current Flutter package is an unsigned engineering preview. `SHA256SUMS.txt` validates contents only. Public v1.11.0 is legacy WinForms. Signing, timestamping, antivirus review, native acceptance and publication authorization remain separate [release gates](RELEASE-POLICY.md).

Use sanitized issue reports. Never attach `auth.json`, raw shared descriptors, tokens, session files or full private transcripts. The screenshot helper writes locally for review; it does not automatically redact or upload. No security software changes, scheduled-task cancellation or live Codex run is implied by this documentation closeout.
