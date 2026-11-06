# Continuum documentation

**Current development baseline:** [`main`](../README.md), formed from Flutter foundation PR #17 and Shared session PR #18 (6 Nov 2026). **Public release state:** historical v1.11.0 WinForms ZIP is still the latest published Release; the Flutter executable is currently an **unsigned engineering preview**.

## Read in this order

| Audience | Document | Scope |
| --- | --- | --- |
| Trying the app | [Root README](../README.md) | What the product is, exact Windows build/run instructions |
| Operator | [User guide](USER-GUIDE.md) | Real workflows, execution modes, account/quota limits, monitoring |
| Operator | [Troubleshooting](TROUBLESHOOTING.md) | Runtime prerequisites, failures, logs and safe recovery |
| Operator | [Security and privacy](SECURITY-AND-PRIVACY.md) | Permissions, local data, owner/viewer trust |
| Developer | [Architecture](ARCHITECTURE.md) | Flutter, Windows bridge, pinned worker and legacy modules |
| Developer | [Shared native terminal](SHARED-NATIVE-TUI.md) | Single-owner TUI attachment, lease, known limitations |
| Developer | [Flutter parity](FLUTTER-PARITY.md) | Historical port checklist; not a blanket acceptance statement |
| Developer | [Quota continuation](QUOTA-CONTINUATION-DESIGN.md) | Implemented bounded design and eligibility |
| QA | [Continuum Windows acceptance](CONTINUUM-WINDOWS-ACCEPTANCE.md) | **Current** native manual gate |
| QA | [Screenshots](SCREENSHOTS.md) | Actual captured evidence and capture protocol |
| Contributor | [Contributing](CONTRIBUTING.md) | Tests, PR hygiene, screenshots, mock-only baseline |
| Maintainer | [Distribution readiness](DISTRIBUTION-READINESS.md) | Adoption obstacles, metrics limitations, next release prerequisites |
| Maintainer | [Release policy](RELEASE-POLICY.md) | Unsigned previews versus signed releases |

## Historical material — retained, not current release instructions

- [Original WinForms README](LEGACY-WINFORMS-README.md): snapshot before the 6 Nov Continuum merge.
- [Original v1.16 Windows acceptance](WINDOWS-ACCEPTANCE.md): for old WinForms PR #16; see **current** gate above.
- [Historical adversarial review](ADVERSARIAL-SOURCE-REVIEW.md), [security review](SECURITY-REVIEW.md), [Flutter behavior audit](FLUTTER-BEHAVIOR-AUDIT.md): contemporary evidence at the commits named in each file, not universal assertions about current `main`.
- [Reusable modules](../components/README.md) and [AeroProgress](../components/AeroProgress/README.md) remain independently documented.

## Evidence standard

Distinguish (1) **mock/source CI**, (2) **Windows built/installed**, (3) **real task execution**, (4) **live shared TUI connection**, and (5) **signing/antivirus/public distribution**. Passing one level **does not** certify the next. Each screenshot should identify the tested commit, mode, outcome and whether it is a historical defect or passing acceptance. **No new Codex run is implied by reading or validating these docs.**