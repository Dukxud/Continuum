# Continuum troubleshooting

Start by identifying the executable and checking its dependencies. The commands below inspect the local environment without scheduling work. See [current state](CURRENT-STATE.md) for recorded builds and known limitations.

## Identify the running version

The default output from [Getting started](GETTING-STARTED.md) is:

```text
%USERPROFILE%\Downloads\Continuum-Preview\Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW\codex_resume_flutter.exe
```

The [public preview](https://github.com/Dukxud/Continuum/releases/tag/v0.1.0-preview.1) can be extracted to any chosen folder. Downloaded review packages have different paths; the [build record](CURRENT-STATE.md#source-layout-preview--11-nov-2026) identifies the verified source-layout preview. The public v1.11.0 release contains the older WinForms app. A GitHub merge does not update an installed executable. Keep each complete package together, including its workers and DLLs.

To inspect the running executable's path:

```powershell
Get-Process -Name codex_resume_flutter -ErrorAction SilentlyContinue |
    Select-Object Id,Path
```

New packages include `build-info.json` beside the executable with the application version, source commit, build time, and tracked/untracked source changes. A source ZIP records archive provenance and no invented commit. For an older package, use its recorded source SHA and checksum. In a source checkout, `git log -1 --format="%H %s"` identifies the commit; `git status --short` shows local changes.

The current `Run-Continuum.cmd` builds a complete source folder by default, including a source ZIP without Git metadata, then opens a fresh verified package under `%LOCALAPPDATA%\Continuum\SourceBuilds`. A runtime-only package opens its own sibling executable after manifest verification. A source folder wins over a stray executable, and an incomplete source/runtime folder fails explicitly. The pinned-preview fallback requires the supplied verifier and checks the cached package on every launch. Replacing just the two launcher scripts cannot install a backend or UI correction; copying them without their verifier now fails explicitly. Use the complete source or application package.

Before launch, the console prints the executable, build identity and effective backend path. If `CODEX_SCHEDULER_SOURCE` is set, the launcher displays that explicit backend override; confirm it identifies the intended source. A source ZIP records `sourceArchive: true` with no invented commit ID. A checkout/worktree records its own Git root and revision, never the revision of an unrelated parent repository. See the [source-build instructions](GETTING-STARTED.md).

Current release builds, including direct EXE launch, require their own adjacent `src/backend/CodexRunEngine.ps1` and `src/desktop/windows_bridge.ps1`. An incomplete package fails instead of loading scripts from a parent checkout or another working directory. Restore the complete package if startup reports a missing bundled backend. For an intentional `CODEX_SCHEDULER_SOURCE` override, use a directory containing both files. Relative values resolve once from the app's startup working directory and become absolute before any bridge call. The normal launcher uses the package directory as that starting location; a manual launch can use a different working directory. An invalid override reports an error without falling back; remove an obsolete override and reopen Continuum to use the bundled backend. These changes do not modify older downloaded executables.

## Repository unresolved, Outside Git, or conflicting checkouts

Select the conversation and check the repository field after lookup finishes. The chooser's `Outside Git:` label can describe its starting folder before a later checkout is found. A saved association takes precedence in that label when available. A startup path such as the user home directory does not prove the conversation never worked in a repository.

The corrected reader uses exact-ID Codex metadata and supported legacy/modern conversation records, including old records in long conversations. A referenced GitHub repository can match an existing checkout by a configured remote even when the local folder has a different name. The search uses conventional development directories and previously verified locations; it does not search every drive or clone a missing repository. **Browse** can select a checkout in another location.

| Message | Meaning and next step |
| --- | --- |
| Repository unresolved | No supported evidence identified an existing Git checkout. Use Browse to choose it. |
| Conflicting checkouts | More than one checkout matches. Use Browse to choose the active checkout. |
| Repository lookup incomplete | A read, identity check, or search limit stopped discovery. Inspect the displayed reason and use Browse for an explicit choice. Partial results are not selected automatically. |
| Repository lookup unavailable | The bridge or its subprocess failed. The repository warning retains the specific error through subsequent usage refreshes; hover for the full message. An unresolved selection can retry on refresh. |

Verified choices are stored under `%LOCALAPPDATA%\CodexResumeScheduler\session-repositories\<session-id>.json`, independently of the current draft and scheduled job. Switching conversations or cancelling a future task should preserve that exact conversation's association. A moved or deleted checkout still needs a new valid choice. If a choice disappears again, record the running package identity and which action preceded it; do not publish raw session IDs, private paths, or rollout contents. The [investigation](REPOSITORY-DISCOVERY.md) records the reproduced defects and verification limits.

## Missing Visual C++ runtime

If Windows reports a missing `VCRUNTIME140.dll`, `VCRUNTIME140_1.dll`, or `MSVCP140.dll`, install the [Microsoft Visual C++ v14 Redistributable (x64)](https://aka.ms/vc14/vc_redist.x64.exe) from Microsoft, then reopen the app. These runtime libraries are required by the compiled Windows application; installing the full Visual Studio build tools is unnecessary for the downloaded preview.

## Several prerequisites fail with the same PowerShell Access denied error

A native Windows test on 18 Nov 2026 stopped **before** dependency validation:
all five reported failures tried to launch the same child
C:\Program Files\PowerShell\7\pwsh.exe, and Windows returned **Access is denied**.
That is **one subprocess-start failure**, not evidence of five missing
installations. It does not establish that Windows Script Host or Visual Studio
is absent.

The older build runner launched each check through an encoded PowerShell
command. The revised runner uses an inspectable source-controlled script via
pwsh -File and probes this shared subprocess boundary once before checking
individual dependencies. PowerShell's [App Control documentation](https://learn.microsoft.com/en-us/powershell/scripting/security/app-control/how-to-use-app-control)
documents a policy that may disallow encoded commands but permit files.
**The user's exact security policy or denial source is not yet known.**

If the subprocess check still reports Access denied, leave security protections
enabled. Inspect the contemporaneous **Microsoft-Windows-CodeIntegrity/Operational**
and **AppLocker** event logs and the endpoint-security product's block history
for the attempted pwsh.exe launch. [Microsoft's App Control troubleshooting
guide](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/operations/appcontrol-debugging-and-troubleshooting)
describes those logs. The preflight does not bypass a deliberate system
restriction. Only after subprocess launch succeeds can Git, Node, Flutter,
C++ and Windows Script Host be evaluated individually.

## Build prerequisites

Current source builds require Windows x64, PowerShell 7.4 or newer, Node.js 22 or newer, Git 2.28 or newer, and Flutter 3.47.9 with its bundled Dart 3.13.7. The preflight checks the pinned Flutter version and the application's Dart `>=3.13.0 <4.0.0` requirement. Keep the committed dependency lock in place.

Run `flutter doctor -v` and inspect its **Windows version** and **Visual Studio - develop Windows apps** sections. Install or repair Visual Studio's **Desktop development with C++** workload, including MSVC x64/x86 tools, CMake and a Windows SDK, and finish any pending reboot. Visual Studio Code alone is not this compiler toolchain. Other doctor findings can concern unrelated platforms. [Official Flutter setup](https://docs.flutter.dev/platform-integration/windows/setup).

The preflight collects independent prerequisite failures into one report. It also runs a disposable Windows Script Host script that only returns a known exit code. If that check reports a missing VBScript engine, inspect Windows **Settings → System → Optional features** and restore the VBScript feature if permitted. If policy blocks it, ask the machine's administrator; Continuum does not change policy or install the feature. [Microsoft's VBScript guidance](https://techcommunity.microsoft.com/blog/windows-itpro-blog/vbscript-deprecation-timelines-and-next-steps/4148301).

### Plugin symbolic links

**Building with plugins requires symlink support** is a Windows capability failure, not a package-version conflict. For error **1314**, open Windows Settings using `ms-settings:developers`, enable [Developer Mode](https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode), then run the same `Run-Continuum.cmd` again. On newer Windows this setting is under **System → Advanced → For developers**; older versions use **For developers**. Enabling it requires permissions allowed by the machine's administrator or organization. Continuum does not change the setting or elevate the build.

Keep other link failures distinct:

| Error | What to inspect |
| --- | --- |
| 1314 / required privilege not held | Developer Mode or the machine's permitted symbolic-link capability. |
| 5 / access denied | Access to the source/link location and the exact target printed by the tool. Enabling Developer Mode does not establish that every folder is writable. |
| 1 / invalid function | Filesystem and source/SDK/cache locations. Flutter suggests a local project location on the same drive as the SDK for this error. |
| Other errors | Preserve the exact stage, exit status and tool output; a different failure is not proof that Developer Mode is missing. |

Flutter recreates plugin links when its plugin list changes. Do not replace them with manually seeded junctions or patch the installed Flutter SDK. A successful capability probe does not certify later downloads, all plugin paths or compilation. Dart's default Windows package cache is `%LOCALAPPDATA%\Pub\Cache`; an explicit `PUB_CACHE` overrides it, and a relative value is resolved from the pub working directory (`src/desktop`). [Dart cache configuration](https://dart.dev/tools/pub/environment-variables).

### Later build stages

Flutter 3.47.9 rejects project-path characters `'#!$^&*=|,;<>?` because of CMake/MSBuild escaping. Use a writable source location with a simple name; spaces and parentheses are supported. The source launcher and direct builder must report prerequisite, runner, locked dependency, analysis, test, compilation and package failures separately. An error prevents later stages and launch; it is not success merely because a prior test passed.

If preflight reports a nondefault Flutter build directory, inspect `flutter config --machine` and use the reported `flutter config --build-dir=build` command before retrying. Continuum packages the x64 release from `build/windows/x64/runner/Release`. If Windows desktop support is disabled, correct the named source of the setting: project `flutter.config`, global Flutter configuration, or `FLUTTER_WINDOWS`. The launcher reports these settings without changing them.

If the builder reports **Review package already exists**, choose a fresh `-OutputDirectory`. It preserves existing packages. If a CI artifact has expired, use the [source-build instructions](GETTING-STARTED.md).

The [delivery audit](WINDOWS-DELIVERY-AUDIT.md) records the exact upstream contracts, corrected paths and the scope of consecutive source checks. Portable regressions do not establish that this Windows computer can complete a native build.

## Weekly appears as five-hour, or a phantom empty row

This was a positional-label bug corrected in PR #22. Current source displays the returned label and window count in Full, Monitor, and Micro. Confirm the running EXE's path: an older package can still show the previous behavior after a source merge.

No usage windows, unknown resets and unavailable reads are different states; do not infer unlimited capacity or a new plan entitlement. Check the selected model and wait for the app's ordinary read-only refresh. [Display contract](QUOTA-PRESENTATION.md).

## Warning triangle in title bar

PR #21 corrected the native icon by installing the Continuum ICO after Windows runner generation. The corrected title-bar icon was observed in Micro view. Check that you launched a package containing that correction. The old triangle alone did not establish a security warning, and the cause of the original substitution was not proven. [Visual evidence](SCREENSHOTS.md).

## Missing model, usage or disabled schedule

Check dependencies without running a model turn:

```powershell
Get-Command node,pwsh,git -ErrorAction Stop | Select-Object Name,Source
Get-Command codex.exe,codex.cmd -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object Name,Source
```

Current source accepts the official native `codex.exe` and the npm `codex.cmd` installation. At least one must appear in the second command's output; restart Continuum after installing Codex or changing `PATH`. Node.js remains required for Continuum's helpers. Confirm that Codex is signed in to the intended account. The app needs a verified workspace, a supported model and reasoning effort, and a current model-matched quota response. Exhausted quota can still permit scheduling for a future time; the worker checks availability again when the job starts. An unavailable or ambiguous metadata response can block scheduling. Inspect the displayed reason and allow the ordinary refresh to complete.

Codex reads its state from `CODEX_HOME` when set, otherwise the Windows user's `.codex` directory. WSL uses a separate Linux home by default. Continuum's Windows process must see the intended installation and state location; it does not search other users' homes or every WSL distribution. See the official [environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables) and [Windows guidance](https://learn.chatgpt.com/docs/windows/windows-app).

## Shared terminal reconnects

The original Shared implementation closed the owner after the scheduled turn, disconnecting its terminal. Current source retains a successful owner for attached clients, with a 15-second no-viewer grace and a two-hour cap. Live verification of this retention behavior remains pending. Later TUI turns are not continuously mirrored by the current host.

Inspect the **specific** job being investigated; do not assume the newest result belongs to it:

```powershell
$dir=Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
Get-ChildItem $dir -Filter 'CodexResume-*.result.json' -File |
  Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name,LastWriteTime
# Replace with the exact affected task name:
$name='CodexResume-YYYYMMDD-HHMM-xxxxxxxx'
$path=Join-Path $dir ($name+'.result.json')
if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Select-Object status,exitCode,at,message}
```

A removed `.shared.json` after cleanup is expected. While a native lease retains the owner, Task Scheduler can still show Running even though the scheduled turn is completed and final disk result is not yet written. An unavailable owner without a result is not automatically success.

```powershell
Get-ScheduledTask -TaskName 'CodexResume-*' -ErrorAction SilentlyContinue | Select-Object TaskName,State
```

## Report a problem

Include the source SHA or package identity, Windows and Codex CLI versions, execution mode, steps to reproduce, and expected versus observed behavior. Include the affected job's sanitized outcome when available. Remove private paths, tokens, raw session IDs, and conversation content before posting. See [security and privacy](SECURITY-AND-PRIVACY.md) and [contributing](CONTRIBUTING.md).
