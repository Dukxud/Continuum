# Continuum documentation index

**Project paused on 6 Nov 2026. Start with [CURRENT-STATE.md](CURRENT-STATE.md).** `main` is the current Flutter baseline, including the native Windows icon (#21) and plan-independent quota presentation (#22). The public v1.11.0 release is the older WinForms generation, not BP211.

| Document | Authority and purpose |
| --- | --- |
| [Current state / handoff](CURRENT-STATE.md) | Baseline commits, executable path, evidence, known limitations and restart instructions |
| [Root README](../README.md) | Product overview, modes, quota compatibility and build/open instructions |
| [User guide](USER-GUIDE.md) | Scheduling, access, live views, quota, persistence and results |
| [Architecture](ARCHITECTURE.md) | Current Flutter/bridge/worker boundaries, ownership and data flow |
| [Quota presentation](QUOTA-PRESENTATION.md) | One/two-window behavior for Plus and Pro; no hard-coded plan assumptions |
| [Shared terminal](SHARED-NATIVE-TUI.md) | One App Server, native clients, lifecycle and limits |
| [Quota continuation](QUOTA-CONTINUATION-DESIGN.md) | Background-only bounded retry policy, independent of quota display |
| [Windows acceptance](CONTINUUM-WINDOWS-ACCEPTANCE.md) | Actual pass/pending distinctions and future native test gate |
| [Troubleshooting](TROUBLESHOOTING.md) | Version confusion, missing quota, reconnects, icons and read-only diagnostics |
| [Security/privacy](SECURITY-AND-PRIVACY.md) | Permissions, stored data, local transport and unsigned binary boundary |
| [Screenshots](SCREENSHOTS.md) | Actual historical evidence, current screenshot status and capture protocol |
| [Flutter developer guide](../flutter_port/README.md) | Source review, complete package build, test commands and icon installation |
| [Contributing](CONTRIBUTING.md) | Explicit authorization, narrow changes, bounded tests and delivery expectations |
| [Release policy](RELEASE-POLICY.md) | Preview versus production release; no publication during the pause |
| [Distribution readiness](DISTRIBUTION-READINESS.md) | Dated adoption evidence and deferred release blockers |
| [Reusable components](../components/README.md) | Independent PowerShell components; not a cross-platform execution promise |

## Historical evidence

[WinForms README](LEGACY-WINFORMS-README.md), [WinForms architecture](history/ARCHITECTURE-WINFORMS.md), [v1.16 Windows gate](WINDOWS-ACCEPTANCE.md), [adversarial review](ADVERSARIAL-SOURCE-REVIEW.md), [security review](SECURITY-REVIEW.md), [Flutter parity](FLUTTER-PARITY.md), and [Flutter behavior audit](FLUTTER-BEHAVIOR-AUDIT.md) are historical records. Their original PR blockers, layouts, build claims and test outcomes do not override the current handoff. Preserve their dates and evidence; do not rewrite a historical failure as success.

All current docs describe the implementation, not a guarantee of current Codex subscription entitlements. For testing, distinguish source/mocks, compiled binary, local launch, live execution, visual acceptance and signed distribution. A merge is not a substitute for a missing test.
