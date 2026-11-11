# Continuum Windows acceptance and evidence

**Current baseline and pause:** [CURRENT-STATE.md](CURRENT-STATE.md). This gate describes future verification, not an instruction to resume work now or reopen already merged PRs. Merge authorization is distinct from a recorded native pass.

## Repository maintenance verification — 11 Nov 2026

[PR #24](https://github.com/Dukxud/codex-resume-scheduler/pull/24) moved the active backend and legacy UI into separate directories and updated runtime snapshots, packaging, and imports. The verified head was `e998e489af688567081209f6b30a18459fd0cb1e`; merge `f72617dd1bbb50722e22780c6f77e740f6d5eae3` has the same source tree.

| Check | Result / boundary |
| --- | --- |
| Local automated checks | 76 Node tests, 40 PowerShell test files, and 104 Flutter tests passed; Flutter analysis had no errors or warnings |
| Hosted Windows build | [Run 43091625553](https://github.com/Dukxud/codex-resume-scheduler/actions/runs/43091625553) passed debug/release compilation, compiled icon verification, and package integrity |
| Downloaded artifact | All 47 manifest entries independently verified; packaged JSON bridge and runtime snapshot checks passed outside the checkout with an isolated profile |
| Local build environment | Runner generation stopped at Flutter's symlink prerequisite; the hosted Windows build passed |
| Native application behavior | No new live Codex or GUI acceptance for this refactor; quota display, Shared retention, and approval scenarios remain open |

The [preview record](CURRENT-STATE.md#source-layout-preview--11-nov-2026) provides the artifact, checksums, expiry, and copy-paste download and launch commands. The earlier evidence below remains tied to its original builds.

## Evidence ledger at pause (6 Nov 2026, Chicago)

| Feature / layer | Evidence | Result / boundary |
| --- | --- | --- |
| Shared backend | BP201: real disposable thread, two viewers, cleanup | Passed that backend probe; not approval/TUI lifecycle certification |
| Remote TUI capability | BP202: installed CLI 0.166.0 reports remote/listener support | Capability check only |
| First native Shared test | Task ran the 90-second command and completed; BP206 result exit 0, descriptor absent | Task completion passed; post-completion TUI reconnected and GUI status was stale |
| Shared retention fix | Run 42249396861 passed; BP207 launch passed | Fixed live post-turn retention and simultaneous approval/question acceptance still pending |
| Native Windows icon | Run 42295808555 plus owner's BP210 Micro screenshot | Icon correction visually confirmed; PR #21 merged |
| Reported quota windows | Run 42327638037 on `796f25e7`; 23 new fixture cases plus full tests/build/package gate | CI passed; PR #22 merge authorized. No BP211 live display screenshot supplied before pause |
| Package integrity | BP211 inner ZIP checksum and 47 manifest entries independently checked | Content verified, not signed publisher authentication |
| Production distribution | No signed Continuum release published | Deferred |

The old [WinForms gate](history/WINDOWS-ACCEPTANCE.md) is historical, not the current Flutter release checklist.

## Future preflight (without a model turn)

- [ ] Record exact source SHA, artifact/run and EXE path; do not mix files from multiple packages.
- [ ] Confirm Windows x64, PowerShell 7, Node, Git and npm Codex dependencies. Record Codex version only with authorized invocation.
- [ ] Review Full/Monitor/Micro at 100% and 125% scaling, date/time entry, Monday-first calendar, view switching, pin, close/save and appearance persistence.
- [ ] Confirm the branded title-bar/Explorer/Alt+Tab icon in the exact binary; BP210 established Micro appearance, not every shell surface forever.
- [ ] Validate runtime and package manifest. Mocks, analysis, compilation and screenshot generation do not establish real Codex behavior.

## Quota regression acceptance (no scheduled turn required)

- [ ] For the same account and model, all three views display the same reported windows and associated percentage/reset.
- [ ] A weekly-only response produces one WEEKLY row/card, no 5-HOUR label and no synthetic second row.
- [ ] A five-hour plus Weekly response produces both rows; reverse order does not exchange meanings or styling.
- [ ] Unknown/empty data is not interpreted as unlimited. Failures show unavailable and recovery restores live data.
- [ ] New Plus/Pro behavior is not inferred from subscription names. Both use the same response-driven rendering.

## Scheduled execution (operator must authorize each live test)

Use a disposable saved conversation and checkout. Never replay real work or grant unrestricted access just to get a green test.

- [ ] Validate repository/branch, account/workspace, model/effort, access and quota before execution. Conflicting/unknown facts block unsafe execution.
- [ ] Overlapping scheduler-owned jobs do not create a second writer. Cancellation is not claimed as termination of a running process.
- [ ] Background produces structured outcomes; quota-only continuation is explicit, Background-only, limited to three and never retries generic errors.
- [ ] Native opens the actual Codex terminal; `finished` means terminal exit, not task-success proof.
- [ ] Shared opens one App Server and native remote client on the original thread without forking.
- [ ] Keep the attached TUI open for at least 30 seconds after the scheduled task completes. No immediate reconnect loop; GUI reports the scheduled result.
- [ ] Exit TUI, observe the no-viewer grace/cleanup and durable outcome; GUI must not retain stale Running after normal cleanup.
- [ ] Verify questions/approvals via each surface, competing answers, disconnects and correct thread/turn scoping.
- [ ] Test later TUI turns explicitly: current host ignores new App Server events after first scheduled completion. Do not assume the GUI mirrors later work.
- [ ] Review two-hour cap behavior and server loss during a retained client; do not call a forced disconnect a graceful native shutdown without evidence.

## Screenshot and release closeout

Follow [SCREENSHOTS.md](SCREENSHOTS.md), using real captures with build/date/outcome and redacted private content. New native results must be recorded, not inferred from previous builds. Signing, antivirus review, consistent versioning, public downloads and release authorization remain separate gates in [RELEASE-POLICY.md](RELEASE-POLICY.md). Development is paused; this is a restart checklist, not an active assignment.
