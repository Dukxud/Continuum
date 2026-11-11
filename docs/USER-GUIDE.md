# Continuum user guide

Schedule saved conversations, monitor reported usage, and inspect results from the Continuum desktop app. For installation, start with [Getting started](GETTING-STARTED.md). The current Flutter version is a Windows engineering preview; feature development is paused.

## Open and prepare

Use the [build and launch instructions](GETTING-STARTED.md) or the recorded preview path in the [project status](CURRENT-STATE.md). Keep the complete package beside `codex_resume_flutter.exe`. Running it requires Windows x64, a signed-in desktop, PowerShell 7, Node, Git and npm Codex with a usable account. Building also requires Flutter and Visual Studio C++ tools.

For a first trial, use a disposable saved Codex conversation and Git checkout. The app reads metadata and usage on startup; a model turn starts when a scheduled job runs. Avoid scheduling a conversation that is already active in another Codex process.

## Main workflow

1. **Choose your thread:** select a saved conversation; check the detected Git root and branch. Use Browse to correct the checkout rather than trusting ambiguous evidence.
2. Choose a catalog-supported **model**, reasoning effort and access. Read-only is appropriate for initial tests. Workspace-write permits intended changes; unrestricted/YOLO disables important safeguards and requires explicit confirmation.
3. In **Set the moment**, enter the local date/time and a concrete instruction. The time editor accepts typed input. Choose **Run in**, then **Schedule once**.
4. Keep Windows awake, online and signed in when the task is due. A countdown reaching zero is not evidence Codex started.
5. Click a running card for live activity, or use **History** for saved responses, worker logs, and execution outcomes.

## Execution modes

| Mode | Execution owner | User interaction | Quota-only continuation |
| --- | --- | --- | --- |
| Background | Pinned noninteractive worker | Logs and saved structured results | Optional, off by default, at most three eligible follow-ups |
| Native terminal | Codex CLI in its terminal | Native TUI; terminal exit is `finished`, not work-success proof | No |
| Shared session | One scheduled App Server | Continuum panel and optional native remote TUI client | No |

For Shared, schedule a new Shared job, open its running card, then choose **Open Codex Terminal** while its owner is accessible. The client uses the original conversation; it cannot attach to arbitrary preexisting CLI processes. Successful scheduled completion may retain the owner while a client stays open, with a 15-second no-client grace and two-hour cap. The GUI's completed status concerns the scheduled turn, not arbitrary later TUI turns. See [Shared limits](SHARED-NATIVE-TUI.md).

## Usage display

Full, Monitor, and Micro display the usage windows Codex reports for the selected model. A five-hour window plus a weekly window produces two rows; a weekly window alone produces one WEEKLY row. Each row includes its remaining percentage and reset time.

The same behavior applies to Plus and Pro accounts. Missing windows do not imply unlimited usage. A failed read shows unavailable until a successful refresh restores the data. Micro shows a countdown for an exhausted window. See the [quota display contract](QUOTA-PRESENTATION.md) for other response shapes and test coverage.

## Views and appearance

**View** selects Full, Monitor, or Micro. **Pin** keeps the window above other applications. **Appearance** previews and saves color and optical choices automatically. Each view retains its window dimensions when the number of reported usage windows changes.

## Persistence and safety

Preferences, job files and pinned runtime snapshots are local under `%LOCALAPPDATA%\CodexResumeScheduler`. Job JSON supplies its transcript path; `*.result.json` supplies the outcome. Prompts and logs can contain private information. Do not upload raw `.shared.json`, transcripts or credentials.

Existing scheduled jobs retain their original runtime when the GUI is upgraded. Closing the GUI or pausing development does not cancel them. Cancellation of a future task is not termination of an already-running Codex process. Worker identity, branch, model and mutex checks remain authoritative.

Quota-only continuation applies only to new opted-in Background tasks with eligible verified exhaustion/reset evidence, matching workspace/model and a readable original thread. It never treats a generic error as permission to retry. A deferred parent is not completed. [Detailed policy](QUOTA-CONTINUATION-DESIGN.md).

## Known preview limitations

Automated tests and Windows package checks pass, while live verification of the latest quota display, Shared terminal retention, and simultaneous approvals remains pending. Shared mode does not continuously mirror later terminal turns after the scheduled turn completes. The [Windows acceptance ledger](CONTINUUM-WINDOWS-ACCEPTANCE.md) records completed checks and open scenarios.
