# Shared Codex owner and native terminal

**Merged, engineering preview; development paused.** PR #18 is part of `main`. See [current state](CURRENT-STATE.md) for baseline and pass/pending evidence. Later icon (#21) and quota (#22) corrections did not change Shared execution.

## Scope and ownership

Continuum schedules one App Server owner for the selected saved conversation. Its GUI uses an authenticated local named pipe. **Open Codex Terminal** launches the real Codex TUI as a remote client of that owner's authenticated loopback listener, with the same thread ID. It does not create a second App Server, a copied conversation or a new scheduled turn.

A Codex process opened independently before Continuum is **not** attachable, mirrorable or transferable in this version. Native terminal mode is different: it launches an ordinary interactive CLI as the execution owner, rather than attaching a client to a Shared owner. Background is noninteractive `exec --json`. Only Background supports optional quota continuation.

## Local transport and permissions

The server binds to `127.0.0.1`, with a random capability token whose SHA-256 verifier appears in server arguments. The raw remote token is passed through the authenticated pipe and native child's environment, not normal snapshots or arguments. The pipe's separate secret is stored in a transient descriptor; do not publish it. These mechanisms are not isolation from a malicious process running as the same Windows user.

Pending requests are validated for supported method and thread/turn identity. Approvals are explicit, with reviewable command/file context. The scheduler's per-session mutex stays with the owner. Multiple clients do not authorize independently competing execution owners or bypass Codex policy. Cross-surface native approvals remain an acceptance item, not a proven consequence of architecture.

## Actual lifetime

1. The scheduled owner resumes the saved thread and starts the saved instruction.
2. `turn/completed` settles the scheduled turn and clears pending requests. The live snapshot reports completed/interrupted/failed.
3. **Successful completion** can retain the server for attached native TUI leases. A 15-second idle grace applies with no leases; a two-hour maximum is measured from entering post-completion retention, not refreshed indefinitely by activity.
4. The Windows worker and mutex remain active during retention; durable `*.result.json` is written when the host exits. Task Scheduler may therefore say Running while the scheduled turn is already completed.
5. On cleanup the owner removes its descriptor/socket. Flutter uses the persisted outcome if the owner is no longer available.

**Important limits:** the host's `onAppMessage` returns after `completed` is set. It does not continue mirroring later TUI turns or forwarding their requests. A retained client is not a fully accepted multi-turn monitoring service. The maximum retention timeout can disconnect an open TUI, including later work; clean native exit is unverified. Failure/server-loss handling after first completion also needs further acceptance. No indefinite daemon is promised.

## Evidence and remaining acceptance

The first real disposable task produced `NATIVE TERMINAL TEST COMPLETE`, but its old server died at completion and the TUI reconnected. BP206 recorded completed/exit 0 with no descriptor. This is historical defect evidence, not a passing lifecycle demonstration.

The lease/fallback fix is merged and Windows mock/build CI passed on `6cd11c6`; BP207 launched. No repeat fixed-binary post-completion TUI pass or dual-surface approval pass was supplied before the pause. BP201 backend and BP202 capability passes do not fill these gaps. Follow [Windows acceptance](CONTINUUM-WINDOWS-ACCEPTANCE.md) only after renewed explicit authorization for live Codex tests.
