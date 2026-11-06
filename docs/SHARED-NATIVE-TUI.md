# Shared Codex terminal integration (draft)

## Authority and scope
A scheduled **Shared session** owns exactly one Codex App Server and starts the saved conversation's scheduled turn. Flutter receives an activity snapshot over the existing authenticated named pipe. A click on **Open Codex Terminal** starts a TUI *client* using `--remote`, `--remote-auth-token-env`, and `resume <same session ID>`. It does not create a new server or fork a thread.

The server listens **only on 127.0.0.1** with a random capability token. Codex receives only the token SHA-256 verifier as a CLI argument; the TUI receives the token through its child-process environment. The token is neither persisted in the job descriptor nor included in status snapshots. Existing scheduled Background and Native terminal modes are unchanged.

## Evidence required before acceptance
- Run the mock protocol regression tests and source/bridge tests. These do **not** run Codex.
- Confirm Windows Flutter analysis/build and inspect the actual GUI.
- **Only with explicit owner authorization**, run a live disposable-thread end-to-end check against the installed Codex CLI, then review question/approval ownership and active-turn TUI behavior.
- Do not merge or release PR #18 before independent review and signed-in Windows acceptance.

Limitation: shared ownership currently follows the scheduled turn's lifetime; TUI connections do not prolong the owner's lifetime after that turn ends. Native rendering and routing of pending approval requests to the TUI are not yet independently verified.
