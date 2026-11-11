# Contributing

Continuum is a personal Windows desktop project. Focused bug reports, documentation corrections, and small, well-explained changes are welcome. Feature development is currently paused; discuss substantial proposals before implementing them.

For the current baseline and known limitations, read the [project status](CURRENT-STATE.md). The [architecture guide](ARCHITECTURE.md) explains how the Flutter interface, Windows bridge, and scheduled worker fit together.

## Report a problem

Include the application build or commit, Windows and Codex CLI versions, execution mode, steps to reproduce, and expected versus observed behavior. State whether the result came from source inspection, a test, or a running Windows application.

Use sanitized examples. Remove account details, personal paths, tokens, session identifiers, and private conversation content from logs and screenshots. See [security and privacy](SECURITY-AND-PRIVACY.md).

## Make a focused change

1. Create a branch from current `main`.
2. Keep the change limited to one problem and update the relevant documentation.
3. Run checks appropriate to the files changed and record the commands and results.
4. Open a pull request that explains the problem, resulting behavior, and remaining limitations.

Flutter owns presentation and windowing. The JSON bridge and pinned worker own Windows scheduling, authorization, and outcomes. Shared sessions have one execution owner with authenticated clients. Keep reusable components independent of application orchestration.

Preserve historical test results and their dates. A source review, successful build, native observation, and signed release establish different things.

## Verify your change

For documentation changes, run `npm ci --ignore-scripts` and `npm run check:docs`, then review code examples and rendered pages. The checker validates tracked local paths and anchors; newly added documents must be staged. Application builds and live Codex runs are not needed for prose edits.

For application changes, use a complete checkout in PowerShell 7:

```powershell
npm ci --ignore-scripts
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
npm test
if ($LASTEXITCODE -ne 0) { throw 'Node tests failed.' }
npm run format:check
if ($LASTEXITCODE -ne 0) { throw 'JavaScript formatting differs.' }
pwsh -NoProfile -STA -File .\src\desktop\Run-WindowsReview.ps1 -TestsOnly
if ($LASTEXITCODE -ne 0) { throw 'Windows/Flutter checks failed.' }
```

The review script checks source and bridge contracts, generates the Windows runner with the pinned icon, restores locked dependencies, and runs strict analysis and tests. The [preview builder](../src/desktop/README.md) adds release compilation and package-integrity verification. Use the [test guide](../tests/README.md) for the complete backend/component acceptance harness and CI coverage. Inspect a failure before rerunning the affected check.

Node mocks and Flutter fixtures do not require live Codex turns. Account interactions, actual scheduled jobs, and native acceptance require explicit operator authorization; use the [Windows acceptance checklist](CONTINUUM-WINDOWS-ACCEPTANCE.md) for those scenarios.

## Review and delivery

For a Windows build, include the exact commit, artifact or local path, checksum, copy-paste launch command, and the behavior verified. Keep previous preview folders intact. Caption screenshots with the build and observed behavior; the [capture guide](SCREENSHOTS.md) covers privacy and provenance.

Maintainer authorization is required before merging a pull request or publishing a release. A documentation change does not resume feature development or satisfy outstanding native acceptance. See the [release policy](RELEASE-POLICY.md).
