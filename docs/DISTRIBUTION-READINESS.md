# Distribution readiness and adoption (6 Nov 2026)

## Current factual state

- Repository visibility: **public** at [Dukxud/codex-resume-scheduler](https://github.com/Dukxud/codex-resume-scheduler).
- The repository was created **27 Oct 2026**, less than two weeks before this review. Its public metadata had **no topics, no homepage, zero stars and zero forks** when inspected on 6 Nov 2026; GitHub's repository description still led with the older "usage resets" scheduler framing, not Flutter/Shared native TUI.
- `main` contains merged Flutter Continuum foundation and Shared native TUI integration (PRs #17 and #18).
- The [latest public GitHub Release](https://github.com/Dukxud/codex-resume-scheduler/releases/latest), **v1.11.0**, is the **older PowerShell/WinForms ZIP**, not the Flutter desktop app. Its release asset is a ZIP, not a signed Continuum installer.
- The current Flutter product has a Windows CI **unsigned preview** and a source build script. CI artifacts have limited retention and are not beginner-friendly install downloads.
- Until this documentation pass, the root README led visitors directly to the legacy release, said "no executable is supplied", and mainly described WinForms. There was no real screenshot gallery in the repository.
- The last published release assets displayed low download counts (single digits per asset, as observed 6 Nov 2026). **Download counts do not equal distinct installs or users**, include repeat/self-downloads, and do not establish zero users. This project has no reported in-app adoption telemetry.

**Conclusion:** Public source availability is **not** equivalent to discoverable, low-friction product distribution. A person seeking Continuum today would have to understand Flutter/PowerShell/Node prerequisites, select an unsigned build, and trust a developer-preview install. A lack of known users under those conditions is unsurprising; attributing it to product quality would be speculation.

## Audience and value proposition

Target: **Windows users of npm Codex CLI** who want to choose an existing conversation, safely schedule the next instruction, see quota context, and optionally interact with the same conversation through a native TUI plus a monitoring window. Differentiators: **three execution modes**, one owner for Shared, Task Scheduler without a persistent GUI service, pinned worker integrity, and deliberately bounded quota continuation.

Do **not** market as: automatic quota bypass, a multi-user cloud product, official OpenAI/Codex, "attaches to any already-running Codex process", general background auto-agent, or a stable cross-platform release.

## Public launch blockers (ordered)

1. **Native acceptance:** Retest fixed Shared TUI lifetime after scheduled-turn completion; dual-surface approvals/questions and native lifecycle, with sanitized screenshots.
2. **Package trust:** Trusted code signing, timestamp, AV/SmartScreen validation. SHA-256 manifests are integrity checks, not trust signatures.
3. **Distributable build:** An accessible, versioned Windows installer or ZIP with predictable binary path and full pinned runtime. No surprise GitHub artifact expiry, no confusing historical release as "latest" for new users.
4. **First-use experience:** Install/readme screenshots, concise 60-second scenario, stable default working directory, error reporting and a direct issue-report path.
5. **Product support:** Compatibility table for supported Codex CLI version(s), reproducible known limitations, changelog, bug/feature labels, release notes and a rollback path.
6. **Discoverability:** Clear public repo name/description/topics/homepage, screenshot hero, link to releases, user-focused demo and targeted feedback requests. Do not purchase promotion or claim adoption on unverified metrics.

## What to measure *without* invasive telemetry

GitHub clone/page/release download metrics (where available), unique external bug reports, successful setup reports, reproducible acceptance logs and voluntary opt-in feedback. These are imperfect indicators. Do not equate release downloads to unique active installations. Ask trial users whether they could install, schedule once, open native terminal, and recover from a failed run.

## Launch policy

This file is a **readiness assessment**, not authorization to publish a production release, change repository marketing metadata, instrument users, create a public signed installer, or run Codex. See [Release policy](RELEASE-POLICY.md).