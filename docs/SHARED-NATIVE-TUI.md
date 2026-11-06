# Shared Codex terminal integration (draft)

## Authority and scope
A scheduled **Shared session** owns exactly one Codex App Server and starts the saved conversation's scheduled turn. Flutter receives an activity snapshot over the existing authenticated named pipe. A click on **Open Codex Terminal** starts a TUI *client* using `--remote`, `--remote-auth-token-env`, and `resume <same session ID>`. It does not create a new server or fork a thread.

The server listens **only on 127.0.0.1** with a random capability token. Codex receives only the token SHA-256 verifier as a CLI argument; the TUI receives the token through its child-process environment. The token is neither persisted in the job descriptor nor included in status snapshots. Existing scheduled Background and Native terminal modes are unchanged.

## Evidence required before acceptance
- Run the mock protocol regression tests and source/bridge tests. These do **not** run Codex.
- Confirm Windows Flutter analysis/build and inspect the actual GUI.
- **Only with explicit owner authorization**, run a live disposable-thread end-to-end check against the installed Codex CLI, then review question/approval ownership and active-turn TUI behavior.
- Do not merge or release PR #18 before independent review and signed-in Windows acceptance.

The host retains the authenticated App Server after scheduled-turn completion while a native TUI holds its local lease. No attached TUI triggers a 15-second idle grace; an attached TUI can remain connected for up to two hours before the owner shuts down. The scheduler's session mutex and task execution remain held during this lease to forbid a second writer; the saved `.result.json` is written when the host exits. Flutter reports scheduled-turn completion from the owner while connected and falls back to the verified persisted job outcome after cleanup.

Remaining limitations: interactive native rendering and question/approval routing require separate signed-in Windows acceptance. A TUI session still open after the two-hour safety bound will lose its server and should close cleanly. No live Codex CLI is run by mock/CI verification.
