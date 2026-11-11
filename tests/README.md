# Testing

Continuum tests the desktop, Windows bridge, worker, protocol, and reusable modules separately. Tests use fixture data, fake task providers, and a mock App Server; they do not request live Codex turns.

## Portable checks

From the repository root with Node.js 22 or later:

```powershell
npm ci --ignore-scripts
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
npm test
if ($LASTEXITCODE -ne 0) { throw 'Node tests failed.' }
npm run check:docs
if ($LASTEXITCODE -ne 0) { throw 'Documentation links failed.' }
npm run format:check
if ($LASTEXITCODE -ne 0) { throw 'JavaScript formatting differs.' }
```

Both `.test.js` and `.test.mjs` files are included. The documentation checker parses tracked Markdown, validates case-sensitive local paths and heading anchors, and ignores external URLs and code examples. It does not establish the availability of external websites.

## Windows checks

Use PowerShell 7, Windows x64, Node.js, Git, and the [desktop build prerequisites](../docs/GETTING-STARTED.md#prerequisites). From a complete checkout:

```powershell
pwsh -NoProfile -STA -File .\src\desktop\Run-WindowsReview.ps1 -TestsOnly
if ($LASTEXITCODE -ne 0) { throw 'Desktop checks failed.' }
pwsh -NoProfile -STA -File .\scripts\Invoke-LocalAcceptance.ps1
if ($LASTEXITCODE -ne 0) { throw 'Backend/component acceptance failed.' }
```

The desktop script generates the runner, installs the icon, checks the real bridge, restores locked dependencies, and runs strict Dart analysis and Flutter tests. Widget tests treat missed hit targets as failures.

The acceptance harness discovers tracked PowerShell, JavaScript, and ES-module test files. Each test process gets separate `LOCALAPPDATA` and `CODEX_HOME` directories; results and logs go into a unique `QA-results-local-*` folder. Native UI tests run in STA. The harness downloads the pinned WebView2 SDK when absent and verifies its digest.

For an auditable clean-checkout run, pass `-ExpectedCommit <full-sha>`. This checks both commit identity and a clean worktree. Omit it for local work in progress. Newly added tests must be staged so Git's inventory includes them.

## Coverage map

| Boundary | Checks |
| --- | --- |
| Desktop state and views | `src/desktop/test/`: schedule logic, quota shapes, view changes, errors, history selection races, appearance, Shared panel |
| JSON/Windows bridge | `flutter-port-bridge.test.ps1`: real subprocess responses with isolated application state |
| Scheduled execution | Worker identity, immutable runtime, task registration, cancellation, model/effort, quota continuation, and durable results |
| Shared session protocol | Mock App Server, authenticated clients, routing, native client leases, completion and cleanup |
| Reusable modules | Unit contracts, independent consumers, native renderers, and standalone package integrity |
| Distribution | Native icon, version-derived preview names, preserved output, ZIP manifests, and bundled dependencies |
| Repository quality | JavaScript and Dart formatting, strict analysis, documentation links, and architecture boundaries |

The `visual-capture` Flutter tag produces fixture images and is excluded from ordinary correctness tests. Fixture images are not live product acceptance.

## CI and manual acceptance

[CI](../.github/workflows/ci.yml) runs portable checks on pull requests and pushes to `main`. Application changes also run the Windows suite, compile the release executable, verify the icon and package, then upload the unsigned preview. Documentation-only changes skip the Windows build.

Automated checks do not establish account compatibility, real task execution, retained terminal behavior, approval handling, native appearance, or release signing. Those observations belong in the [Windows acceptance ledger](../docs/CONTINUUM-WINDOWS-ACCEPTANCE.md), with exact build identity and operator authorization.
