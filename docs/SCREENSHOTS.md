# Continuum screenshots and capture standard

**Policy:** Screenshots are actual captures of the Windows application, not generated illustrations or Flutter mockups. Label source, date, build SHA, mode, and acceptance state. Do **not** use a screenshot showing a known defect as the public product hero.

## Existing evidence — historical failure (6 Nov 2026)

The operator captured a real **BP204** Shared-session test showing the Continuum **Live activity** panel and a real Codex terminal side by side. The scheduled 90-second task responded `NATIVE TERMINAL TEST COMPLETE`, but the TUI then displayed `Reconnecting to server` and Flutter showed `Shared session is not accessible` with stale Running status. This was **not a passing acceptance screenshot**.

**Status:** A subsequent fix kept the owner alive while a native TUI lease is open and added persisted-outcome fallback. The Windows mock/build gate passed; the fixed behavior still needs new signed-in Windows evidence. A current hero screenshot must be captured only after that pass.

> The original operator screenshot is included in the conversation evidence, **not automatically published to this public repository**. The repository does not yet contain an authorized, sanitized current product screenshot. Use the capture process below and add real files here after reviewing for personal data.

## Screenshot checklist for a credible public gallery

1. **Full window** — conversation, repository, model/quota, date/time, execution mode, upcoming runs.
2. **Monitor and Micro** — compact views, optionally pinned on top, no clipped controls.
3. **Appearance** — both Colors and Optics tabs with actual liquid optics, not a fabricated render.
4. **Shared live activity** — meaningful running event and Open Codex Terminal button.
5. **Native TUI** — original Codex terminal *attached to the same Shared session* (one owner).
6. **Completed** — GUI reports Completed and attached TUI remains connected; capture after a 30-second post-turn observation.
7. **Recent result** — correctly labels a completed/failed/blocked outcome, redacted private logs.

The first six should be captured after the latest lifecycle acceptance. If a screenshot is from another commit, put it under `docs/screenshots/historical/` and describe its specific outcome rather than treating it as current.

## Capture without starting Codex

1. Open the Continuum window you wish to document; for live shots, operator authorization to run Codex is separately required.
2. Run the **read-only window capture** helper from PowerShell 7, selecting a suitable window title:

```powershell
pwsh -NoProfile -File .\scripts\Capture-ContinuumScreenshot.ps1 -Name full -WindowTitleRegex 'Continuum|Codex Resume Scheduler'
```

For an attached native terminal, specify `-Name native-tui -WindowTitleRegex 'Continuum viewer'`. The script captures the matching **window** to the private review folder `%USERPROFILE%\Pictures\Continuum-QA` and does **not** upload, execute Codex, create tasks, or modify the application.

3. **Open and redact each image** before adding to the repository: account/profile names, Windows paths, Codex UUIDs, instructions, transcript text, workspace names if private, network/credentials, and adjacent applications. Do not distort statuses or error messages; if redaction would misrepresent the test, use a new disposable conversation.
4. Copy reviewed images to `docs/screenshots/` and reference them from this guide/README with captions including the SHA, date and mode.
5. Validate rendered images in GitHub's Markdown renderer at normal browser zoom. Commit only sanitized images and link them with relative paths.

## Distinguish screenshots from tests

A static screenshot proves what appeared at a moment, not that the full execution path passed. Record task outcome, exact build and log summary in the [native acceptance checklist](CONTINUUM-WINDOWS-ACCEPTANCE.md). PNG/WebP file content should remain in the repository; **never commit raw user screenshots containing secrets**.