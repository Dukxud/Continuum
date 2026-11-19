# Repository discovery investigation

The first sections record the 18 November 2026 investigation of PR #31. The failing baseline is
`152b15b212afff6981efc45e642d6f0a2a59f09e`. Source inspection and isolated regressions
establish the defects below; they do not establish which installed executable or
rollout format was present on an inaccessible Windows computer.

The [18 November runtime follow-up](#runtime-follow-up--18-november-2026) records
the subsequent failure after PR #31 was merged. Earlier passing fixtures did not
exercise every subprocess boundary or every persisted Codex path representation.

## Why retaining the previous selection was insufficient

The earlier change retained a verified repository under the exact conversation
UUID in `settings.json`. It could preserve a successful lookup or manual selection,
but could not manufacture the first successful lookup. The reader still discarded
several legitimate forms of Codex evidence and stopped reading partway through
long conversations. No association could be saved for an unresolved conversation.

There was also a distribution problem: the source launcher and the rejected
launcher-only ZIP contained no application payload. Without an executable beside
it, the launcher opened the pinned public preview. Changing those two scripts
alone could not update the repository reader inside the installed application.

## Complete path trace at the failing baseline

| Stage | Source | Behavior and consequence |
| --- | --- | --- |
| Launcher | [Run-Continuum.ps1](../Run-Continuum.ps1) | A sibling executable selects a manifest-verified local package. Otherwise it opens or downloads the pinned public preview. Source archives do not run their own backend by default. |
| Backend location | [windows_scheduler_adapter.dart](../src/desktop/lib/windows_scheduler_adapter.dart) | An explicit environment override wins; otherwise executable ancestry identifies the bundled bridge. Release builds do not use an unrelated working directory as fallback. |
| Session inventory | [CodexData.ps1](../src/backend/CodexData.ps1), `Get-RecentCliSessions` | Reads the first record of each rollout, admits only verified CLI/exec UUIDs, deduplicates IDs, and returns the 30 most recently modified sessions. The starting directory is a hint, not necessarily the current checkout. |
| Picker label | [ReadModels.ps1](../src/desktop/bridge/ReadModels.ps1), `Get-FlutterSessionChoices` | Git/Outside Git reflects the starting directory. Optional names and previews join by full UUID. The label is not the result of repository resolution. |
| Initial load and refresh | [scheduler_controller.dart](../src/desktop/lib/scheduler_controller.dart) | Restores the selected session and draft, then resolves an empty repository. Repeats unresolved lookups on full refresh. A nonempty preserved/manual value suppresses automatic replacement. |
| Session switch | Same controller, `selectSession` | Clears the repository and queues a preference save before requesting another lookup. Selection/edit epochs reject stale responses. The debounced save must not discard the previous session's last association. |
| Metadata read | [windows_bridge.ps1](../src/desktop/windows_bridge.ps1), `select`; [CodexUsage.js](../src/backend/CodexUsage.js) | Verifies the local selected session, requests `thread/read`, and passes the reported directory to the resolver. The original PowerShell facade discards other returned metadata. |
| Direct and stored evidence | `Find-SessionRepository` | Checks reported CWD, startup CWD, exact-ID saved association, and matching scheduled-job payloads. Each path is checked with Git. A valid reported root wins while alternatives remain visible. Multiple fallback roots remain ambiguous. |
| Recent rollout evidence | Same function | Reads only the final 800 lines, then retains at most eight turn contexts and twelve tool directories. Older `turn_context` evidence disappears as a conversation grows. |
| Reference fallback | [CodexSessionRepository.ps1](../src/backend/CodexSessionRepository.ps1) | Reads only the first 16,000 lines/32 MiB. Recognizes legacy user events and function calls; ignores modern completed items and `response_item` user messages. The middle of a long rollout can fall outside both readers. |
| Local checkout matching | Same file | Searches conventional development directories to bounded depth. At baseline, compares only `origin`, recognizes HTTPS/SCP GitHub URLs, and reduces a multiword heading to its first word. All matches still require a real local Git root. |
| Picker-preview fallback | `windows_bridge.ps1`, `Get-CodexPickerPreview` | Used only after no result; another `thread/list` process supplies a preview. At baseline, only a heading in that preview is used, so an explicit repository URL is lost. An existing conflict is not overridden. |
| Lookup response | Controller `_resolveRepository` | Publishes the root, alternatives, and warning, then queues a save. Manual edits and newer selections win over a late result. |
| Preferences | [Preferences.ps1](../src/desktop/bridge/Preferences.ps1) | Validates the request, preserves the exact-ID map, migrates the previous draft, verifies new paths with Git, and writes settings. SettingsStore provides atomic replacement, not concurrent transactions. |
| Scheduling | [Scheduling.ps1](../src/desktop/bridge/Scheduling.ps1) | Revalidates the selected session, repository root, branch, account/model, time and conflicts. Saves the job and pinned runtime; a picker caption is never scheduling authority. |
| Cancellation | `windows_bridge.ps1`, `cancel` | The task provider first refuses unsafe cancellation. Successful cancellation writes an outcome and deletes the job payload, removing that payload as future repository evidence. A durable session association must survive independently. |
| Restart | Controller load and resolver | Restores one draft and resolves other exact-ID associations/evidence when selected. It cannot restore an association that was never discovered, never saved, or existed only in a deleted task payload. |

The original startup/refresh omission was already documented and corrected during
the Flutter migration. The [historical behavior audit](history/FLUTTER-BEHAVIOR-AUDIT.md)
is evidence of that earlier defect, not proof that the current parser handles every
Codex record format.

## Schema evidence

The audit compared the reader with official Codex source at
[`b82943092cf52b69ab13ab1a5bb2beb7820deef7`](https://github.com/openai/codex/tree/b82943092cf52b69ab13ab1a5bb2beb7820deef7).

- [Rollout summaries](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/rollout/src/list.rs)
  explicitly distinguish legacy `UserMessage` events from paginated
  `ItemCompleted(UserMessage)` events and support both.
- [Turn item types](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/protocol/src/items.rs)
  define `UserMessage.content`, `CommandExecution.cwd`, and `McpToolCall.arguments`.
  User text parts have the `text` discriminator defined in
  [user_input.rs](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/protocol/src/user_input.rs).
- [Protocol records](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/protocol/src/protocol.rs)
  retain session Git metadata, legacy execution CWD, legacy MCP invocation
  arguments, and thread/turn attribution on completed items.
- [PathUri](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/utils/path-uri/src/lib.rs)
  serializes command CWD as a `file:` URI. Treating that value as a literal native
  filesystem path loses valid evidence, including paths with encoded spaces.

These are specific schema omissions, rather than a reason to inspect arbitrary
assistant prose or execute stored tool code.

## Implemented lookup and persistence

The current lookup follows these boundaries. Every automatic path still requires
an existing local checkout verified by Git; an owner/repository name is search
evidence, not a checkout path.

| Boundary | Implemented behavior |
| --- | --- |
| Conversation inventory | A metadata-only Codex `thread/list` requests `cli` and `exec` sources ordered by `updated_at`. Plain local rollout headers remain the offline fallback. The picker displays the 30 most recently updated verified conversations. |
| Selected conversation | Exact-ID `thread/read` retains CWD, preview, Git identity, source, and rollout path. An older conversation can be verified even when it is outside the displayed 30. An explicit unsupported source is rejected; a stale local record cannot override it. Missing or compressed local rollouts can use supported exact-ID Codex metadata. |
| Rollout evidence | The reader scans the selected file's initial byte snapshot, including old evidence between the former head/tail windows. It recognizes the legacy and modern schemas above, full user previews, local `file:` paths, and structured tool arguments. A foreign header invalidates the scan. Assistant prose, tool-result prose, malformed JSON, and code comments do not supply repository evidence. |
| Local matching | Explicit paths can point outside conventional search locations. Reference-only evidence searches bounded conventional development directories and previously verified locations. All configured Git remotes are checked, including `upstream` and SSH URL forms. Explicit owner/repository identities match exactly; whole project names retain their words and may match a repository's complete name component. A lone first word is not substituted for a multiword project. |
| Choice and UI ordering | A verified reported CWD remains authoritative while other candidates are disclosed. Without it, multiple verified fallback roots stay unresolved. A restored manual choice is revalidated. Manual edits and newer selections beat late lookup results; switching threads saves the outgoing choice before requesting the next repository. |
| Persistence | Verified choices are stored under the full conversation UUID in independent atomic files. Save, schedule, and cancellation boundaries preserve that association. Legacy maps and drafts migrate without replacing a newer explicit selection. |

The independent record is
`%LOCALAPPDATA%\CodexResumeScheduler\session-repositories\<session-id>.json`.
Its schema is `{ "schema": 1, "sessionId": "<full UUID>", "root": "<Git root>" }`.
The ordinary `settings.json` draft remains separate. Replacing the draft, changing
threads, or deleting a future task's payload therefore does not delete another
thread's association. On reuse, the stored path is checked with Git again. Known
paths from other records only extend search locations; they do not assign another
conversation's repository to the selected conversation.

The picker uses an exact-ID saved association for its `Git:` label when available,
then the initial CWD. An `Outside Git:` label can therefore precede a successful
lookup from later conversation evidence. The repository field and its warning
describe the current lookup result:

| Result | Meaning and UI behavior |
| --- | --- |
| Resolved | A verified root fills the repository field. Other verified candidates, when present, remain visible for review. |
| Conflicting | Several matching checkouts exist and none has authoritative precedence. The field remains empty; the user chooses with Browse. |
| Unresolved | No supported evidence identifies a verified local checkout. The field remains empty; the user chooses with Browse. |
| Incomplete | A read, identity check, or resource bound prevents a complete fallback search. The field remains empty and the reason is shown. A partial candidate set is not reported as unique. |
| Unavailable | The bridge or metadata operation failed. The UI reports the failure and can retry an unresolved lookup on refresh. |

## Regression evidence

The independent [repository-evidence regression](../tests/session-repository-evidence.test.ps1)
ran against the unchanged baseline with PowerShell 7.7.0 and real disposable Git
repositories. It made no Codex calls, network requests, scheduled tasks, or Actions
runs. Of 18 cases, five passed and thirteen failed.

| Baseline failure | Reproduction |
| --- | --- |
| Saved Git identity ignored | Session metadata names the remote; the original directory is outside Git and a uniquely matching checkout exists elsewhere. |
| Old turn context lost | The valid context precedes 901 unrelated records. |
| Middle of long rollout skipped | Explicit repository evidence occurs after line 16,000 and before 901 newer records. |
| Alternate user format ignored | `response_item/message`, `role=user`, with an explicit GitHub URL. |
| Paginated user format ignored | `event_msg/item_completed/UserMessage` with explicit text evidence. |
| Paginated command ignored | Completed `CommandExecution` with a local `file:` CWD URI outside conventional search directories. |
| Paginated MCP call ignored | Completed `McpToolCall` with an explicit `repository_full_name` argument. |
| Legacy execution event ignored | `exec_command_begin` and `exec_command_end` with structured CWD. |
| Legacy MCP event ignored | `mcp_tool_call_begin` and `mcp_tool_call_end` with invocation arguments. |
| Preview URL ignored | Selected Codex preview contains a full repository URL but no Markdown heading. |
| Multiword project truncated | `# Black Ignition` with separate Black-Ignition and Black-Foundry remotes. |
| Other configured remotes ignored | Explicit GitHub identity is configured as `upstream`, without `origin`. |
| SSH URL form ignored | Checkout remote uses `ssh://git@github.com/owner/repository.git`. |

The five passing controls cover the existing legacy user URL, multiple matching
checkouts staying ambiguous, assistant/tool-result/malformed text being ignored,
foreign completed-item thread identity being ignored, and explicit tool CWD
outside the home search locations.

### Reader and persistence correction verification

After the implementation, all original 18 cases passed. Adversarial review added
nine more checks: header identity changes, code comments/string literals, exact
BOM/CRLF snapshots while a file grows, oversized records, scan deadlines, partial
directory enumeration, remote `file:` authorities, existing association retention,
and concurrent migrations versus an explicit selection. The resulting suite
passed **27 of 27 cases in 5.307 seconds** on Linux with PowerShell 7.7.0.

[CodexRepositoryEvidence.ps1](../src/backend/CodexRepositoryEvidence.ps1) now reads
an exact initial-byte snapshot through a bounded stream. It handles the documented
legacy and paginated evidence types, complete user previews, native paths and local
`file:` URIs. It does not inspect arbitrary assistant/tool-result prose or infer
executed arguments from code comments. An explicit foreign session header stops
the scan. The default 12-second read budget and 8,388,608-character record limit produce an
explicit incomplete result when reached; partial evidence cannot be called unique.

Checkout enumeration is lazy, limited to the conventional roots and previously
verified locations, with a 10-second/20,000-directory bound. Reparse directories
are not followed. A resource limit returns an incomplete result, not the first
matching checkout. Candidate roots remain Git-verified, and explicit remote
identities are compared exactly. The scanner reads every configured remote and
preserves whole project names.
The direct-path verification loop also checks an eight-second budget. These bounds
are checked during streaming and between filesystem/Git operations; they are not
a promise that the operating system can interrupt a blocked external operation.

Durable associations use one atomic file per session. Migration publishes with
no-replace semantics, so a concurrent explicit selection wins independently of
write order. The concurrency regression starts three migration writers and one
explicit writer in separate PowerShell runspaces. Legacy root comparisons
normalize slash spelling before comparing Git's canonical root.

### Verification scope

These results were obtained on the Linux development host. They describe the
source under review, separately from earlier recorded Windows package checks.

| Check | Observed result and scope |
| --- | --- |
| Repository evidence | All 27 isolated real-Git cases passed, including the 13 reproduced baseline failures and the adversarial limits/trust/persistence cases above. |
| Existing PowerShell source suites | `repository-detection`, `session-repository-reference`, `session-repository-persistence`, `session-discovery-sources`, `session-activity`, `settings-persistence`, and `flutter-port-source` passed. These are source/fixture checks, not Windows Task Scheduler execution. |
| JSON bridge integration | `repository-bridge-flow.test.ps1` passed. The production dispatcher ran in fresh child PowerShell processes through the real Node metadata helper, Git reader, preference handlers, and cancellation path. Codex App Server responses and Windows task APIs were fixture providers. |
| Flutter | All 116 tests passed, including eight new repository continuity cases. Analyzer and formatting checks passed. No native Windows UI was launched by these checks. |
| Node metadata | All 12 targeted thread-metadata cases passed after source-kind validation was corrected. |
| Full Node run | 80 of 83 tests passed. Three unrelated Shared-session failures involved host Unix-socket `EPERM` and a mock timeout; this run is not described as an entirely passing suite. |

No GitHub Actions were used and no merge was performed for this investigation.
A native Windows build, the Windows launcher/package smoke, and the actual user's
installed application were not run on this Linux host. A real signed-in Codex
service was not substituted for the deterministic metadata fixtures. Source
verification does not demonstrate that an existing installed executable updated
itself; the complete application package must carry the corrected backend and UI.

## Requirements preserved

- Resolve only the selected verified session; never borrow another conversation's
  saved repository or a foreign completed item's identity.
- Reverify every candidate with Git. A remote-only conversation does not create a
  checkout, and a missing path is not an existing repository.
- Preserve ambiguity when multiple local checkouts genuinely match. A displayed
  title or arbitrary assistant text cannot authorize one of them.
- Keep manual selections and asynchronous selection/edit ordering intact.
- Persist associations independently of cancellable task payloads.
- Limit filesystem discovery to known roots; reading one selected rollout does
  not authorize a drive-wide scan, network clone, or execution of its contents.
- Keep worker-time validation and previously pinned jobs unchanged. Source and
  fixture verification are separate from native Windows acceptance.

## Documentation read

All 35 Markdown files tracked at the baseline were read in full, including
historical records and repository templates. Historical merge/CI instructions were
treated as dated evidence; the current instruction not to use Actions takes
precedence.

| Area | Files |
| --- | --- |
| Project | `README.md`; `.github/CONTRIBUTING.md`; `.github/PULL_REQUEST_TEMPLATE.md`; `.github/ISSUE_TEMPLATE/bug_report.md` |
| Current documentation | `docs/README.md`; `ARCHITECTURE.md`; `CURRENT-STATE.md`; `GETTING-STARTED.md`; `USER-GUIDE.md`; `TROUBLESHOOTING.md`; `CONTRIBUTING.md`; `CONTINUUM-WINDOWS-ACCEPTANCE.md`; `RELEASE-POLICY.md`; `SCREENSHOTS.md`; `SECURITY-AND-PRIVACY.md`; `SECURITY-REVIEW.md`; `SHARED-NATIVE-TUI.md`; `QUOTA-CONTINUATION-DESIGN.md`; `QUOTA-PRESENTATION.md` |
| History | `docs/history/README.md`; `ADVERSARIAL-SOURCE-REVIEW.md`; `ARCHITECTURE-WINFORMS.md`; `DISTRIBUTION-READINESS.md`; `FLUTTER-BEHAVIOR-AUDIT.md`; `FLUTTER-PARITY.md`; `LEGACY-WINFORMS-README.md`; `WINDOWS-ACCEPTANCE.md` |
| Source and components | `src/README.md`; `src/backend/README.md`; `src/desktop/README.md`; `components/README.md`; `components/AeroProgress/README.md` |
| Tests and legacy package | `tests/README.md`; `legacy/winforms/README.md`; `legacy/winforms/PACKAGE-README.md` |

## Runtime follow-up — 18 November 2026

Dates in this follow-up use the client's America/Chicago time zone.

The new baseline is PR #31's merged source, `7f083df`. The reported screen says
**Repository lookup unavailable; retrying automatically**. That text comes from
the controller's exception path. It establishes that the operation failed, rather
than successfully reporting no matching checkout. The old interface replaced the
useful exception with that generic warning and a subsequent successful usage
refresh cleared the separate error. The original exception is therefore not
recoverable from that screenshot alone.

This investigation reproduced the following defects independently. They are
concrete failures in the source, not a claim that one specific fixture matches the
unavailable Windows installation's original error.

### Runtime and schema failures reproduced

| Path | Reproduction and correction |
| --- | --- |
| Codex installation → metadata helper | The old resolver required `codex.cmd` and an adjacent npm JavaScript entry. Official Codex also supports native Windows installation. `CodexCli.ps1` now resolves native `codex.exe` or the supported npm entry, and consumers pass the correct native/JavaScript launch form. Node remains a Continuum dependency. |
| Metadata helper → npm wrapper → native server | A child fixture returned valid metadata, then retained inherited output pipes after its npm wrapper was killed. The old helper printed successful JSON but did not exit before a four-second test deadline. The corrected helper first closes input, waits for graceful completion, then applies bounded cleanup to its own process tree. Official npm layouts use their native binary directly where available. |
| PowerShell child → Dart transport | A real child process showed that stream decoding could fail independently while the adapter awaited exit. The shared production transport now attaches both output consumers immediately, waits for exit and stream completion under one deadline, drains diagnostic bytes without requiring UTF-8, and reports invalid JSON-output encoding as a controlled error. |
| Bridge exception → repository field | An actual dispatcher error was lost after a successful quota refresh. The repository warning now retains that exception and exposes the complete text in its tooltip. A later response still cannot overwrite a newer conversation selection or manual edit. |
| Persisted command URI → Git inspection | Codex reserves `file:///%00/bad/path/<base64>` for paths that cannot be represented as ordinary local URIs. Decoding it created a native NUL path. On PowerShell 7.7, `Test-Path` threw before the Git reader's exception handler, aborting discovery even when another valid checkout was present. The decoder rejects this opaque representation and native NUL hints; Git path inspection also contains path exceptions. |
| Persisted `local_shell_call` → evidence parser | A real Git fixture with the repository only in `action.working_directory` remained unresolved. The parser now reads this explicit field for the documented `exec` action. It does not parse the command text. |
| Persisted `thread_settings_applied` → evidence parser | A real Git fixture with the repository only in `thread_settings.cwd` remained unresolved. This event records successful persistent settings updates, including directory changes before another turn. The parser now reads the CWD and explicit runtime workspace roots, accepts legacy records without `thread_id`, and rejects snapshots owned by a different thread. |

The opaque-path regression first failed all four initial cases against the merged
baseline on PowerShell 7.7. After path containment, the additional persisted-shell
and settings positives still failed on both PowerShell 7.7.0 and 7.4.0. With the
parser corrections, all nine initial runtime-path cases passed on both versions.
Three further checks cover reuse of one acquired snapshot after the live file
changes, the latest structured turn model in the same pass, and an expired shared
lookup budget returning an incomplete result. The resulting **12 cases passed**
on PowerShell 7.7.0 and 7.4.0 (1.812 seconds and 1.954 seconds respectively).
These fixtures use actual local Git checkouts and isolated application directories.

Selection now acquires one evidence snapshot for repository and model extraction.
Optional metadata and preview work precede that read, and directory/remote
verification reuses its results. The reference-matching pass does not repeat Git
checks for direct evidence paths already verified. A shared 40-second budget accounts for metadata,
history scanning and Git verification, leaving room within the adapter's
55-second deadline. An expired fallback lookup reports incomplete; an already
verified authoritative reported root retains its established precedence. These
checks occur between operations and do not promise to interrupt a blocked native
Git or filesystem call.

The five Dart subprocess regressions run the real PowerShell child and production
JSON dispatcher. Four failed before the transport/controller correction. All five
passed afterward: durable dispatcher errors, late-error protection for a manual
choice, a Unicode checkout with metadata unavailable, invalid diagnostic-stream
bytes with valid JSON output, and controlled rejection of invalid output encoding.
The complete Flutter run passed **120 tests**, with **one explicit skip** for the
native Windows adapter on Linux. Strict analysis and formatting passed.

The final repository/backend gate passed ten PowerShell suite files:
`repository-detection`, `session-repository-reference`,
`session-repository-persistence`, `session-repository-evidence` (27 cases),
`session-discovery-sources`, `session-activity`, `settings-persistence`,
`flutter-port-source`, `repository-runtime-paths` (12 cases), and
`repository-bridge-flow`. The last runs the actual JSON dispatcher in fresh
children and passed after the shared-budget and single-snapshot changes.
The separate `codex-cli-resolution` suite also passed.

The full Node run reported **85 passes out of 88 tests**. The same three Shared
session failures involved Unix-socket `EPERM` and a mock timeout on this host;
this is not an entirely passing Node suite. Targeted runtime regressions cover
the actual subprocess launch and shutdown failure independently of those socket
tests. The metadata/discovery/title/launch group passed **15 of 15**; the
launch/Shared/usage/model group passed **23 of 23**. These groups share the three
launch cases and must not be added as disjoint totals.

### Delivering the source correction through the established launcher

The previous default source-ZIP route still selected the old pinned preview. That
could leave a source fix entirely outside the running application. The existing
`Run-Continuum.cmd` now builds a complete source folder by default, whether it is
a source archive, checkout or worktree. It creates a fresh complete package under
`%LOCALAPPDATA%\Continuum\SourceBuilds\<unique-id>`, verifies it and starts it.
The required Windows build tools must be installed; missing tools produce an
explicit error, with no SDK installation or older-application fallback.

A runtime-only package still opens its own manifest-verified sibling executable.
Complete source wins over a stray executable, and incomplete source/runtime
folders fail. Only a folder containing the launcher alone retains the pinned
public-release route. The launcher prints the executable, source/build identity
and effective backend, including any `CODEX_SCHEDULER_SOURCE` override.

Source archives are identified as archives with no fabricated commit. Git build
identity is accepted only from the actual source root, including worktrees, so an
archive unpacked inside an unrelated parent repository cannot inherit that
parent's revision. Source-mode unblocking is restricted to required scripts and
rejects linked paths; execution policy is unchanged. These source/decision checks
do not constitute a Windows build or an observed native launch.

The old routing failed six of eight portable decision cases. The corrected and
expanded launcher suite passed **12 of 12**, including real linked-directory and
linked-file rejection. The separate source-identity suite passed **seven of
seven** using actual clean/dirty Git repositories, untracked source, a worktree,
ordinary archives, an archive inside an unrelated repository, and broken Git
metadata. The existing preview-version metadata suite also passed. Updated
Windows launcher fixtures parse, but their execution and a compiled Windows EXE
remain untested on this Linux host.

The subsequent [Windows delivery audit](WINDOWS-DELIVERY-AUDIT.md) records the
source-build prerequisite correction and later packaging/launcher changes. Its
current fallback requires the supplied package verifier; the two launcher files
alone are insufficient, and cached pinned packages are verified on every launch.

### Official contracts checked

The authoritative Codex source remains pinned to
[`b82943092cf52b69ab13ab1a5bb2beb7820deef7`](https://github.com/openai/codex/tree/b82943092cf52b69ab13ab1a5bb2beb7820deef7).
The audit read the actual source behind each newly reproduced record:

- [PathUri conversion](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/utils/path-uri/src/lib.rs#L108-L118)
  defines the opaque path sentinel and its platform-specific byte encoding.
- [Response items and local shell actions](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/protocol/src/models.rs)
  define `local_shell_call`, `action.type`, and `working_directory`.
- [Thread settings snapshots](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/protocol/src/protocol.rs#L2553-L2590),
  [their emission](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/core/src/session/thread_settings.rs),
  and [resume metadata extraction](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/state/src/extract.rs)
  establish the settings CWD, runtime roots and ownership rules.
- [Rollout persistence policy](https://github.com/openai/codex/blob/b82943092cf52b69ab13ab1a5bb2beb7820deef7/codex-rs/rollout/src/policy.rs)
  confirms that local shell calls and settings snapshots are durable evidence.

The persistence review also corrects the interpretation of two earlier fixture
categories. At this pinned revision, `exec_command_begin` and `exec_command_end`
are transient events; accepting one if explicitly present does not prove it will
exist in an ordinary saved rollout. Legacy history omits completed command items,
whereas paginated history retains them. Legacy `mcp_tool_call_end` is persisted.
The warehouse-only `executed_tool_calls` metadata is explicitly ignored when Codex
deserializes old records. It is not a public substitute for missing structured
history, and Continuum does not infer executed calls from arbitrary Code Mode
JavaScript, comments, quoted output, or assistant prose.

The official documentation review covered these pages and the sections bearing
on installation, storage, selection, paths and process communication:

| Official page | Scope read and checked |
| --- | --- |
| [App Server](https://learn.chatgpt.com/docs/app-server) | Stdio protocol, initialization, metadata-only `thread/read`, list ordering and filters, thread/item pagination, command and dynamic-tool schemas, events, errors and remote Code Mode hosting. |
| [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) | Complete installation and CLI overview, including native Windows and npm alternatives. |
| [Environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables) | Complete page: `CODEX_HOME`, SQLite state location, installer location and standalone cache. |
| [Advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced) | Profiles and precedence, state home, project configuration, root markers and history persistence. |
| [Developer commands](https://learn.chatgpt.com/docs/developer-commands) | Interactive/app-server entrypoints, exec/resume/fork, directory/worktree commands and global flag behavior. |
| [Noninteractive mode](https://learn.chatgpt.com/docs/non-interactive-mode) | Complete page: explicit-ID resume, ephemeral runs, stdout/stderr and JSON output. CLI execution events are not assumed to be identical to stored rollout records. |
| [Windows app](https://learn.chatgpt.com/docs/windows/windows-app) | Complete page: native and WSL execution, installation/PATH, Git and separate default homes. |

The documented `thread.id` identifies the selected conversation; the newer
`sessionId` describes a shared session tree and is not interchangeable with it.
Metadata-only reads do not resume a conversation or start a turn. Default list
ordering differs from Continuum's intentional update-time ordering. The audit
preserved exact-ID selection and CLI/exec source checks rather than broadening
the scheduler to every App Server source kind.

All **36 tracked Markdown files** were reread for this follow-up: the 35-file
inventory above plus this investigation. Historical build and CI records remain
dated evidence. No GitHub Actions were invoked.

### What this follow-up does and does not establish

A genuine `@openai/codex` 0.170.0 App Server was also exercised in an isolated
`CODEX_HOME`, without account credentials or model turns. Initialization and
read-only thread metadata requests succeeded through both the native and npm
entry paths. This checks the current protocol and launch mechanism beyond mocks;
it does not reproduce the user's private session history or account state.

The opt-in `tests/genuine-codex-repository-probe.ps1` then exercised the complete
PowerShell dispatcher → installed-command resolver → Node helper → genuine Codex
→ Git path. Exact metadata (795 ms), chooser load (1,120 ms), repository selection
from a current checkout (2,030 ms), preference save (813 ms), and selection for an
outside-Git conversation through its exact remote and an existing known checkout
(1,847 ms) all passed. The probe uses disposable application/Codex state, empty
file-based credentials and no inherited tokens. Windows task enumeration is
stubbed; no account, model-turn, resume or scheduling request is made.

The development host is Linux. No native Windows UI/build or Task Scheduler
acceptance result is implied by the portable PowerShell, Node and Flutter checks.
The screenshot's original hidden exception and the exact installed package still
remain unverified. The corrected error path preserves the concrete failure if
one remains after these fixes. No merge or GitHub Actions run was performed for
this follow-up.
