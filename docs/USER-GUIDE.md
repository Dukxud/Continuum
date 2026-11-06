# Continuum user guide (Windows Flutter preview)

## Before you schedule

1. Install Node.js, Git, PowerShell 7 and npm Codex CLI; sign in through Codex.
2. Make sure there is a saved Codex conversation and a local Git checkout.
3. Obtain and launch the **current Flutter preview** using the exact [root README build instructions](../README.md#install-and-open-the-current-continuum-preview-windows). The [public Release download](https://github.com/Dukxud/codex-resume-scheduler/releases/latest) is the older WinForms generation.
4. Start with a **disposable conversation** and **Read-only** access until you know which execution mode you want.

Continuum is a **local scheduler**, not a hosted Codex account, a subscription bypass or a background cloud agent. It uses Windows Task Scheduler. The scheduled device must be available at execution time.

## Main window

- **Choose your thread:** Select a saved conversation. The app attempts a read-only repository lookup and allows an override. Check the Git root/branch before scheduling; a conversation can reference another checkout.
- **Capacity / Live:** Usage is read from Codex App Server for the available model. Percentages and resets are informational and may be unavailable, stale, or ambiguous. Model and effort choices depend on the live catalog.
- **Set the moment:** Pick local date/time, enter an instruction, choose access and execution mode, then **Schedule once**. Controls support manual time entry.
- **Upcoming / Recent:** Upcoming shows pending/running tasks; Recent provides outcomes and logs. A countdown reaching zero is **not** proof the Codex turn ran.
- **View / pin:** Switch Full, Monitor and Micro; optional Always on Top is a window setting, not an external PowerToys dependency. Appearance choices are separate and persist without a second save dialog.

## Execution mode comparison

| Mode | When to use it | Interaction | Completion meaning |
| --- | --- | --- | --- |
| **Background** | Noninteractive continuation, logs, bounded quota retry | No live TUI; inspect history/log | Structured worker result reflects the verified exit/turn status |
| **Native terminal** | You want Codex's ordinary interactive console to own the run | Native Codex questions/approvals in terminal | **Finished** means the terminal process exited; inspect the conversation for work completion |
| **Shared session** | You want Continuum live monitoring plus an optional native terminal client | One App Server owner, optional TUI via **Open Codex Terminal**, pending requests in Continuum | Scheduled turn can report **Completed** while attached viewer keeps owner online for a bounded time |

A shared session **must be started by Continuum**. It does not discover, mirror or supplant a process already open in an unrelated Codex terminal. In particular, do not schedule a second writer against an actively used conversation. [Shared implementation](SHARED-NATIVE-TUI.md).

### Shared session step-by-step

1. Schedule a new **Shared session** in a disposable conversation. Set Read-only unless you have an explicit need for write access.
2. Wait for Windows Task Scheduler to start the job. Click its **running** card to open **Live activity**.
3. Click **Open Codex Terminal** *while the owner is accessible*. This starts a **TUI client**, not a second App Server, not a second scheduled turn and not a fork.
4. When the scheduled turn finishes, the host records **Completed**. With an attached terminal it can remain online; when no viewers are attached it has a 15-second grace. A two-hour maximum bounds a forgotten client. When the owner closes, the GUI uses the saved `.result.json` instead of a stale Running snapshot.
5. Exit the native terminal when done; check **Recent runs** and conversation history to confirm what happened.

**Known QA boundary (6 Nov 2026):** The first native session test completed the intended 90-second command but exposed a server shutdown/reconnect defect. A lifecycle fix was merged with mocked/Windows build verification; a **repeat live acceptance and simultaneous approval/question test remain unverified**. See [acceptance gate](CONTINUUM-WINDOWS-ACCEPTANCE.md).

### Background and quota-only continuation

For **new Background** schedules, an off-by-default switch allows up to **three** quota-only follow-up tasks, and **only** if the worker observes an eligible, verified model-specific rate limit with a supported future reset. A generic error, unverified workspace, ambiguous reset, active writer, missing conversation or unrelated exception is **not** eligible. A deferred parent is **not** a successful completed turn. Automatic quota continuation is **not supported for Native or Shared**. [Policy details](QUOTA-CONTINUATION-DESIGN.md).

## Model, access and identity

Models/efforts come from Codex, not from a hard-coded model whitelist. Access choices are **Read-only**, **Workspace-write**, and **unrestricted/YOLO**. YOLO may operate beyond the chosen repository without sandboxing or approval. Never enable it simply to make a test pass.

Before execution, a pinned worker checks account/workspace identity, repository, branch, runtime integrity, and applicable quota; if it cannot verify necessary facts, it blocks the job rather than guessing.

## Persistence and shutdown

- Scheduling writes local Windows tasks, job JSON and immutable runtime snapshots under `%LOCALAPPDATA%\CodexResumeScheduler`.
- Recent outcome records use `*.result.json`; logs and Codex conversation files may contain private content.
- Closing the GUI does **not** cancel already registered scheduled jobs.
- In Native mode the terminal is the live interaction owner. In Shared mode the **server** is the scheduled owner; the attached TUI is a client. During an attached viewer lease, the Windows task/mutex can remain active even after the scheduled turn reports Completed.
- Cancellation of a not-yet-started task is **not** equivalent to terminating a running Codex process. Verify actual state.

## Common questions

**Can it connect to Codex I opened before launching Continuum?** No. The current Shared feature attaches only to a Shared job launched by Continuum.

**What if the weekly limit is low?** Usage cards report Codex-provided state. They cannot grant more capacity. Only bounded Background continuation can automatically reschedule on an eligible verified reset.

**Where is the EXE?** For the documented local build: `%USERPROFILE%\Downloads\Continuum-Main\CodexResumeFlutter-Windows-v0.2-UNSIGNED-PREVIEW\codex_resume_flutter.exe`. Keep the whole extracted folder intact.

**What if a terminal says "Reconnecting to server"?** Inspect whether the Shared owner is still online and whether its task has completed. The original lifecycle bug is documented; the latest fix needs a new manual acceptance test. [Troubleshooting](TROUBLESHOOTING.md).