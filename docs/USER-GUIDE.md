# Continuum user guide

Schedule saved conversations, monitor reported usage, and inspect results from the Continuum desktop app. For installation, start with [Getting started](GETTING-STARTED.md). The current Flutter version is a Windows engineering preview; feature development is paused.

## Open and prepare

Use the [build and launch instructions](GETTING-STARTED.md) or the recorded preview path in the [project status](CURRENT-STATE.md). Keep the complete package beside `codex_resume_flutter.exe`. Current source requires Windows x64, a signed-in desktop, PowerShell 7.4 or newer, Node, Git and an installed Codex CLI with a usable account. It accepts native `codex.exe` or the npm installation on `PATH`; older preview packages retain their recorded prerequisites. Building also requires Flutter 3.47.9 with its bundled Dart SDK, Visual Studio C++ tools and plugin symbolic-link capability described in the setup guide.

For a first trial, use a disposable saved Codex conversation and Git checkout. The app reads metadata and usage on startup; a model turn starts when a scheduled job runs. Avoid scheduling a conversation that is already active in another Codex process.

## Main workflow

1. **Choose your thread:** select a saved conversation; check the detected Git root and branch. Use Browse to correct the checkout rather than trusting ambiguous evidence.
2. Choose a catalog-supported **model**, reasoning effort and access. Read-only is appropriate for initial tests. Workspace-write permits intended changes; unrestricted/YOLO disables important safeguards and requires explicit confirmation.
3. In **Set the moment**, enter the local date/time and a concrete instruction. The time editor accepts typed input. Choose **Run in**, then **Schedule once**.
4. Keep Windows awake, online and signed in when the task is due. A countdown reaching zero is not evidence Codex started.
5. Click a running card for live activity, or use **History** for saved responses, worker logs, and execution outcomes.

### Choosing the repository

The conversation's starting folder can be outside Git even when later messages or tool calls identify the checkout. The chooser's `Git:` label uses a saved association when available, then that starting folder; check the resolved repository field after selecting the conversation. Discovery uses verified Codex metadata, supported conversation evidence, and existing local Git checkouts.

If the app reports **Conflicting checkouts**, choose the intended checkout with **Browse**. **Repository unresolved** means no supported evidence identified a local checkout. **Repository lookup incomplete** means the search could not finish; its reason is displayed. Browse supplies an explicit choice in each case. An unavailable lookup can retry on refresh. See [repository troubleshooting](TROUBLESHOOTING.md#repository-unresolved-outside-git-or-conflicting-checkouts).

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

Preferences, job files, repository associations and pinned runtime snapshots are local under `%LOCALAPPDATA%\CodexResumeScheduler`. Job JSON supplies its transcript path; `*.result.json` supplies the outcome. Prompts and logs can contain private information. Do not upload raw `.shared.json`, transcripts or credentials.

A verified repository choice is saved separately for each full conversation ID in `session-repositories/<session-id>.json`. It survives changing the current draft, switching conversations, and cancelling a future task. The app verifies that the saved checkout still exists when it is reused; another conversation's saved choice is not assigned to the selected thread.

Existing scheduled jobs retain their original runtime when the GUI is upgraded. Closing the GUI or pausing development does not cancel them. Cancellation of a future task is not termination of an already-running Codex process. Worker identity, branch, model and mutex checks remain authoritative.

Quota-only continuation applies only to new opted-in Background tasks with eligible verified exhaustion/reset evidence, matching workspace/model and a readable original thread. It never treats a generic error as permission to retry. A deferred parent is not completed. [Detailed policy](QUOTA-CONTINUATION-DESIGN.md).

## Known preview limitations

Earlier Windows package checks are recorded in the [Windows acceptance ledger](CONTINUUM-WINDOWS-ACCEPTANCE.md). The repository-discovery correction has automated source, bridge and Flutter coverage on Linux; its native Windows build and UI have not been verified on that host. Live verification of the latest quota display, Shared terminal retention, and simultaneous approvals remains pending. Shared mode does not continuously mirror later terminal turns after the scheduled turn completes. See the [repository verification scope](REPOSITORY-DISCOVERY.md#verification-scope) for the current correction.
