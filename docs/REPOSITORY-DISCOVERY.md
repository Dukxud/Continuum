# Repository discovery investigation

This records the 18 November 2026 investigation of PR #31. The failing baseline is
`152b15b212afff6981efc45e642d6f0a2a59f09e`. Source inspection and isolated regressions
establish the defects below; they do not establish which installed executable or
rollout format was present on an inaccessible Windows computer.

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
