# Opt-in quota continuation — architecture, detailed design, acceptance

Status: implementation candidate for draft PR #17. Owner authorized implementation on 4 Nov 2026. No merge or publication authorization.

## Architecture and decision

The **Flutter UI** collects one opt-in choice on a new schedule. The **Windows JSON bridge** validates and persists a versioned policy. The **immutable, pinned PowerShell worker** remains the sole authority for unattended execution. A small Codex-specific **quota continuation policy/service** classifies terminal CLI evidence, checks the current model's authoritative App Server reset, creates at most one safe child task, and records parent→child provenance. The existing **OneTimeTasks**, **JobOutcomes**, **SettingsStore**, repository, mutex, workspace and runtime-fingerprint components remain authoritative.

No CLI auto-resume flag, daemon, timer loop, UI-dependent watcher, generic failure retry, parsing of a human reset date, or mutation of preexisting jobs. Ordinary new scheduling remains one-time by default. Older `autoResume=true` payloads **must not** gain new behavior.

## Data and contracts

- New jobs explicitly opt into `continuationPolicy: {schema:1,mode:"quota-only",maxContinuations:3}`. When off, store `null` or omit. Never infer from historical fields.
- Root job has `retryAttempt:0`; child increases it by one. Maximum three child executions per chain. `rootJob`, `parentJob`, `nextJob`, and a child-registration intent provide traceability. No renaming or re-execution of the parent.
- The job's account hash, session UUID, Git root, branch, model, reasoning, permission, pinned runtime fingerprint and instruction are preserved. Each child revalidates all of them before Codex execution; the resume instruction tells Codex to inspect progress and avoid repeating completed actions.
- A *post-execution* deferral requires nonzero CLI exit, terminal structured `turn.failed` event with an unambiguous quota error, no subsequent successful turn or conflicting thread/persistence failure, matching verified workspace, matching model quota bucket, denied current attempt, authoritative `exhausted-window` reset, valid future UTC seconds and a safe local non-DST-ambiguous trigger. Arbitrary stderr, agent text, stale errors or generic failures never qualify.
- A *pre-execution* deferral is allowed only if the same verified model/account reports an actual exhausted-window reset; otherwise record the current blocked result.
- Schedule once at the exact verified reset plus **one minute**. Reject resets already passed or more than 14 days away. Do not poll, round away seconds, fall back to unverified times or force a retry if the original execution was successful.
- Only one follow-up may be registered per parent. Persist a durable child intent before registration; if re-invoked, reconcile existing intent with Windows instead of making a second child. The parent outcome is `deferred` with `nextJob` only after OS registration succeeds; otherwise report a failure or blocked reason. No claims of completed work until Codex actually exits successfully.
- A task manually cancelled while still pending is never recreated by a background process. Explicit scheduled sibling jobs for the same session are treated as a conflict. Do not start a second writer. A failed verification, unknown identity, changed repository/branch, missing thread, exceeded attempt cap or unverifiable reset ends the chain.
- The GUI shows opt-in before scheduling and presents pending quota children as **Waiting for quota**, retaining the normal cancellation boundary. Once closed, Windows Task Scheduler, not Flutter, owns the follow-up.

## Adversarial acceptance specification

A01 Opt-in absent/off → no auto-follow-up after any failure; old `autoResume=true` alone stays inert.

A02 Opt-in on + terminal quota event + matching, blocked, exhausted model quota with future reset → exactly one child at reset+60s, exact seconds preserved, parent `deferred` with linked child.

A03 Quota already exhausted at scheduled start → defer without launching Codex, subject to identical verification.

A04 Successful Codex exit, generic error, stale limit event followed by completion, writer conflict, missing thread, or backend resets unrelated to the model → **no child**.

A05 Missing/changed workspace, branch, session, runtime fingerprint, model, permissions, stale/unverified reset, ambiguous DST trigger or malformed payload → fail closed, no child.

A06 Three child attempts maximum; attempt 3 quota failure terminates as blocked/failed without creating attempt 4.

A07 Crash/re-run after intent: no duplicate child; when registered, recover the parent link without executing Codex again; uncertain/incomplete registration requires review.

A08 Manual cancellation of a pending child leaves the chain stopped; running jobs cannot be falsely cancelled. Concurrent same-session work remains mutually excluded.

A09 Flutter choice defaults off, restores and saves accurately, travels through the JSON bridge and never makes a task with missing authorization; switch remains usable at normal/compact window sizes.

A10 Exact-head Windows isolated fake-CLI and fake-Task Scheduler tests, old WinForms acceptance, Flutter controller/widget tests, pinned-runtime build and artifact-integrity checks pass. Native BLACK-PUDDLE dry-run and independent code review remain prerequisites to completion.
