# Shared Codex owner and native terminal (current design, not fully accepted)

**Status:** Merged into `main` on 6 Nov 2026 via [PR #18](https://github.com/Dukxud/codex-resume-scheduler/pull/18), on top of Flutter foundation PR #17. **The source merge is complete; native lifecycle and simultaneous approval/question acceptance are not.** No public signed release has been made.

## Authority and scope

A scheduled **Shared session** starts **exactly one** Codex App Server as execution owner for the selected saved conversation. Continuum's Live activity panel connects through an authenticated local named pipe. Clicking **Open Codex Terminal** launches a genuine Codex TUI in remote-client mode:

```text
codex --remote <loopback App Server> --remote-auth-token-env <private env var> resume <same session ID>
```

This is an explanation of the invocation shape, **not a command to run independently** without the owner-supplied credentials. A TUI window attaches to the **same saved thread**; it does not start another App Server, a second turn owner, or a copied conversation. **A separately running Codex process launched before Continuum is not attachable/mirrorable/supplantable by this version.** Concurrent independent writers are not allowed.

## Security boundary

- App Server is bound to **`127.0.0.1`** and authenticated using a random capability token; the server receives only a SHA-256 verifier in command arguments.
- Continuum holds its separate local named-pipe secret in the per-job descriptor. The TUI's raw remote token is returned only via an authenticated named-pipe message and passed in the child environment, never published in status snapshots or normal logs.
- Request IDs and thread/turn IDs are verified before exposing or accepting a question/approval. Unknown request types, cross-thread approvals and implicit permission escalation fail closed.
- The active owner holds the per-session scheduler mutex. A TUI is a **viewer/client**, not a competing scheduled worker. This does not make the local account a privilege boundary against itself.

## Completion and cleanup lifecycle

The scheduled turn can complete **before** the native TUI window closes. After a verified `turn/completed`:

1. The owner publishes the real `completed`, `interrupted` or `failed` status.
2. The owner retains the App Server while any native terminal lease is attached. A **15-second** idle grace applies when none is attached.
3. A **two-hour maximum** caps a forgotten viewer. The server can disconnect after this bound.
4. The scheduled worker writes durable `*.result.json` when the owner exits. Flutter reads live snapshots while available, then uses the **persisted** outcome after owner cleanup instead of indefinitely displaying stale Running status.
5. The temporary shared descriptor/socket is cleaned up. Absence of `*.shared.json` **after** completion is expected.

**Tradeoff:** While a native TUI remains attached after the scheduled turn, the Windows scheduled task and per-session mutex remain held. This preserves single-writer authority but may keep Windows Task Scheduler showing Running after the turn itself reports Completed.

## Actual evidence (6 Nov 2026)

- **Mock/CI passed:** on `6cd11c6`, Windows source/bridge checks, Node fake App Server tests, Flutter analysis/widget tests, release build and archive checksum checks passed ([run 42249396861](https://github.com/Dukxud/codex-resume-scheduler/actions/runs/42249396861)).
- **Target-machine preview launched:** BP207 launch PASS on BLACK-PUDDLE.
- **Original live test:** A 90-second disposable task replied `NATIVE TERMINAL TEST COMPLETE`. In the earlier build, the real TUI then showed `Reconnecting to server` because the App Server was terminated at turn completion, while Flutter reported inaccessible and retained stale Running status. BP206 showed `completed`, exit code 0, and removed descriptor. This **demonstrated the defect**, not acceptance.
- **Fix merged:** Native TUI holds an authenticated named-pipe lease; owner waits after turn completion and falls back to durable status. Tests cover bounded idle, maximum lifetime, cleanup and transition. **A repeat live post-completion TUI test against the fixed binary and dual-surface approvals are still required.**

## Next manual acceptance

Use [the current Continuum Windows acceptance gate](CONTINUUM-WINDOWS-ACCEPTANCE.md), **only after the operator explicitly authorizes a disposable live Codex task**. The critical checks are: one owner, same conversation, terminal stays connected for at least 30 seconds after the scheduled turn completes, correct persisted status after terminal exit, and valid approvals/questions without duplicates. Save sanitized images using [the screenshot guide](SCREENSHOTS.md).

This design is not an open-ended daemon, a bypass of Codex's usage limits, or a general-purpose attachment feature for any preexisting Codex terminal.