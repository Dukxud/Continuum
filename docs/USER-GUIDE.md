# Continuum user guide

Schedule saved conversations, monitor reported usage, and inspect results from the Continuum desktop app. For installation, start with [Getting started](GETTING-STARTED.md). The current Flutter version is a Windows engineering preview; feature development is paused.

## Open and prepare

Use the [build and launch instructions](GETTING-STARTED.md) or the recorded preview path in the [maintainer handoff](CURRENT-STATE.md). Keep the complete package beside `codex_resume_flutter.exe`. Running it requires Windows x64, a signed-in desktop, PowerShell 7, Node, Git and npm Codex with a usable account. Building also requires Flutter and Visual Studio C++ tools.

Start with a disposable saved Codex conversation and Git checkout. The app reads metadata and usage on startup; no model turn is submitted merely by opening the GUI. Do not schedule an independently active conversation for a second writer.

## Main workflow

1. **Choose your thread:** select a saved conversation; check the detected Git root and branch. Use Browse to correct the checkout rather than trusting ambiguous evidence.
2. Choose a catalog-supported **model**, reasoning effort and access. Read-only is appropriate for initial tests. Workspace-write permits intended changes; unrestricted/YOLO disables important safeguards and requires explicit confirmation.
3. In **Set the moment**, enter the local date/time and a concrete instruction. The time editor accepts typed input. Choose **Run in**, then **Schedule once**.
4. Keep Windows awake, online and signed in when the task is due. A countdown reaching zero is not evidence Codex started.
5. Click a running card for live activity, or use History for retained results. A scheduled task's result is not the same thing as a launched preview's result.

## Execution modes

| Mode | Execution owner | User interaction | Quota-only continuation |
| --- | --- | --- | --- |
| Background | Pinned noninteractive worker | Logs and saved structured results | Optional, off by default, at most three eligible follow-ups |
| Native terminal | Codex CLI in its terminal | Native TUI; terminal exit is `finished`, not work-success proof | No |
| Shared session | One scheduled App Server | Continuum panel and optional native remote TUI client | No |

For Shared, schedule a new Shared job, open its running card, then choose **Open Codex Terminal** while its owner is accessible. The client uses the original conversation; it cannot attach to arbitrary preexisting CLI processes. Successful scheduled completion may retain the owner while a client stays open, with a 15-second no-client grace and two-hour cap. The GUI's completed status concerns the scheduled turn, not arbitrary later TUI turns. See [Shared limits](SHARED-NATIVE-TUI.md).

## Usage display — both Plus and Pro

All three views use the actual windows Codex reports for the selected model, **not a subscription name or list position**. Five-hour plus Weekly yields two correctly labeled rows; Weekly alone yields one WEEKLY row; other reported durations retain their labels. No missing second row is fabricated. Empty data is not unlimited usage. A failed read reports unavailable; a later successful read restores returned data.

Each label remains with its own remaining percentage/reset. Weekly styling follows that window even when it is first or alone. Micro retains exhaustion countdowns. Changing plan or switching view does not require a different app build. This is display support for both account types, not a guarantee of any plan's current limits. [Quota contract](QUOTA-PRESENTATION.md).

## Views, appearance and icon

View selects Full, Monitor or Micro. Pin controls native Always on Top. Appearance previews and persists color/optical choices without a second Save action. The Continuum icon is now pinned in Windows builds and was visually accepted in BP210 Micro. The quota patch removes absent rows but leaves native window dimensions unchanged; it is not an automatic window-shrinking feature.

## Persistence and safety

Preferences, job files and pinned runtime snapshots are local under `%LOCALAPPDATA%\CodexResumeScheduler`. Job JSON supplies its transcript path; `*.result.json` supplies the outcome. Prompts and logs can contain private information. Do not upload raw `.shared.json`, transcripts or credentials.

Existing scheduled jobs retain their original runtime when the GUI is upgraded. Closing the GUI or pausing development does not cancel them. Cancellation of a future task is not termination of an already-running Codex process. Worker identity, branch, model and mutex checks remain authoritative.

Quota-only continuation applies only to new opted-in Background tasks with eligible verified exhaustion/reset evidence, matching workspace/model and a readable original thread. It never treats a generic error as permission to retry. A deferred parent is not completed. [Detailed policy](QUOTA-CONTINUATION-DESIGN.md).

## Acceptance boundary

BP211 CI and package integrity passed; no post-fix live quota screenshot was supplied before pause. The Shared retention fix and simultaneous native/GUI approvals still require their separate tests. The owner authorized merging, not a declaration that every native scenario passed. Nothing further is required from the operator during the pause. [Future test checklist](CONTINUUM-WINDOWS-ACCEPTANCE.md).
