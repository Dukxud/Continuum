# Windows scheduling backend

These scripts serve the current Flutter application and the retained WinForms interface. They handle account/model metadata, job persistence, scheduling policy, execution, and results.

| Entry point | Responsibility |
| --- | --- |
| [Invoke-CodexJob.ps1](Invoke-CodexJob.ps1) | Run one saved job without loading a GUI |
| [CodexRunJob.vbs](CodexRunJob.vbs) | Launch the worker through Windows Script Host and preserve its exit code |
| [CodexRunEngine.ps1](CodexRunEngine.ps1) | Validate the pinned runtime and execution context, then run the selected mode |
| [CodexData.ps1](CodexData.ps1) | Read conversations, repositories, preferences, and job status |
| [CodexUsage.js](CodexUsage.js) | Read Codex account, model, thread, and rate-limit metadata |

The [Flutter bridge](../../flutter_port/windows_bridge.ps1) and legacy UI publish snapshots from the repository or package root. `Get-CodexRuntimeFiles` is the allowlist of root-relative paths copied into each immutable runtime. It includes this directory and the required reusable components, without the legacy UI.

New packages and snapshots preserve `src/backend/` and `components/`, so imports resolve the same way in a checkout and in a deployed package. Existing scheduled jobs retain their original runtime files. Do not move files inside an already-published snapshot.

See [architecture](../../docs/ARCHITECTURE.md) and [contributing](../../docs/CONTRIBUTING.md) for verification commands.
