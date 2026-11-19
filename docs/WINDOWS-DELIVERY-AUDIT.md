# Windows delivery and runtime audit

## Post-merge Windows finding — 18 Nov 2026

Native execution of merge commit 8d66da3b707010686af8a176568353edbcea9472
stopped before the build or tool checks. The shared subprocess helper attempted
to start C:\Program Files\PowerShell\7\pwsh.exe from src\desktop and received
Access denied. This happened once for each requested tool and was incorrectly
reported as five unrelated prerequisites (Git, Node, Flutter, Visual Studio,
and Windows Script Host). No package compilation occurred.

Source trace: Get-ContinuumWindowsBuildTools calls
Invoke-ContinuumBuildProcess for every tool; the helper always first starts a
PowerShell owner with an encoded command, including when the actual target is
an EXE. Flutter batch files incurred an additional encoded PowerShell child.
Windows refused the first owner at process creation. The exact Windows
security/ACL cause is not proven from this log.

Follow-up candidate changes the owner to a static, source-trusted .ps1 invoked
with -File, executes batch files within that owner, and first verifies the
shared process boundary. If it is still denied, the launcher reports **one
underlying blocker** and explicitly does not attribute it to missing tools.
No security controls are disabled or changed.

The earlier three clean rounds were **portable source checks on Linux**, and
did not cover this Windows process-start scenario. They must not be presented
as native Windows acceptance. This post-merge issue remains open until a
fresh native Windows run verifies the new candidate.

Baseline: `ab94244d260cd02c66989620307c62e2ec206ab2`, after PR #32.
The reported source launch reached Flutter package restoration, then failed while
creating Windows plugin symbolic links. Continuum added the generic message
`Flutter dependencies failed`. The application had not compiled or launched.
The earlier repository/transport checks did not establish Windows build readiness.

This record separates the reported Windows failure, source-backed findings,
portable regression evidence and native acceptance. No GitHub Actions, operating
system setting changes, elevation or Flutter SDK patches are part of this work.

**Final review result:** three consecutive complete source/portable rounds passed
on the same 263-file input digest after correcting the findings below. Each round
included the root review and three independent reviews of all 12 routes. This
does not establish native Windows build or application acceptance on the user's PC.

## Upstream contracts checked

The installed SDK source is Flutter **3.47.9**, revision
[`c197ca5199e9ee5661e865596c9c07294dfab51c`](https://github.com/flutter/flutter/tree/c197ca5199e9ee5661e865596c9c07294dfab51c),
with Dart **3.13.7**, revision `416e33b0ffaef062a60ec966bb8c82ed2b83f128`.
Its source checkout was clean when inspected. The web documentation describes
newer releases, so version-specific behavior below comes from that pinned source.

| Contract | Evidence and implication |
| --- | --- |
| Plugin links | [`flutter_plugins.dart`](https://github.com/flutter/flutter/blob/c197ca5199e9ee5661e865596c9c07294dfab51c/packages/flutter_tools/lib/src/flutter_plugins.dart), `createPluginSymlinks`, `_createPlatformPluginSymlinks`, `refreshPluginsList`: plugin directories use Dart `Link.createSync`. A changed plugin list invokes `force: true`, deleting and recreating the link directory. Precreating junctions cannot satisfy this path reliably. |
| Error classification | The same file's `handleSymlinkException` distinguishes Windows error **1314** (missing privilege), **5** (access denied), and **1** (invalid function, with a project/SDK location hint). Only the privilege case establishes the Developer Mode remedy; an unrelated file error must retain its own detail. |
| Windows privilege | Microsoft's [CreateSymbolicLinkW contract](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createsymboliclinkw) defines the unprivileged-create flag and Developer Mode prerequisite. [Settings for developers](https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode) explains the user-controlled setting and organizational restrictions. Application code cannot grant a missing Windows privilege. |
| Visual Studio | Flutter's [Windows setup guide](https://docs.flutter.dev/platform-integration/windows/setup) requires the C++ desktop workload and Windows/Visual Studio doctor checks. Pinned [`visual_studio_validator.dart`](https://github.com/flutter/flutter/blob/c197ca5199e9ee5661e865596c9c07294dfab51c/packages/flutter_tools/lib/src/windows/visual_studio_validator.dart) also handles incomplete/nonlaunchable installations, pending reboot, missing MSVC/CMake components and missing Windows SDK. Command presence is insufficient. |
| Project path | Pinned [`windows/build_windows.dart`](https://github.com/flutter/flutter/blob/c197ca5199e9ee5661e865596c9c07294dfab51c/packages/flutter_tools/lib/src/windows/build_windows.dart) rejects `'#!$^&*=\|,;<>?` in the project path because of CMake/MSBuild escaping. Spaces and parentheses are allowed; a preflight must not invent broader restrictions. |
| Architecture | Pinned [`commands/build_windows.dart`](https://github.com/flutter/flutter/blob/c197ca5199e9ee5661e865596c9c07294dfab51c/packages/flutter_tools/lib/src/commands/build_windows.dart) selects ARM64 on an ARM64 host. Continuum's package contract is x64 and its release path is `build/windows/x64/runner/Release`; this mismatch must be diagnosed before building. |
| Flutter configuration | Pinned [`build_info.dart`](https://github.com/flutter/flutter/blob/c197ca5199e9ee5661e865596c9c07294dfab51c/packages/flutter_tools/lib/src/build_info.dart) uses the global `build-dir` setting. Continuum packages from `build`, so a conflicting setting is diagnosed before compilation. [`flutter_features_config.dart`](https://github.com/flutter/flutter/blob/c197ca5199e9ee5661e865596c9c07294dfab51c/packages/flutter_tools/lib/src/flutter_features_config.dart) resolves Windows support from project configuration, global configuration, then `FLUTTER_WINDOWS`; the pinned Windows feature otherwise defaults to enabled. |
| SDK and Git versions | `pubspec.yaml` requires Dart `>=3.13.0 <4.0.0`; the committed lock remains enforced. The source-build bridge fixture uses `git init -b`, documented in [Git 2.28](https://git-scm.com/docs/git-init/2.28.0.html). Node's repository contract is version 22 or newer. The supported PowerShell floor for the new process helpers is 7.4. |
| Package cache | [Dart pub environment variables](https://dart.dev/tools/pub/environment-variables) documents `%LOCALAPPDATA%\Pub\Cache` and `PUB_CACHE`. Dart 3.13.7 pins [pub `ec276d10a7fa0f6c6ec005340fb9ad29f3b012d0`](https://github.com/dart-lang/pub/blob/ec276d10a7fa0f6c6ec005340fb9ad29f3b012d0/lib/src/system_cache.dart); its cache resolver returns an explicit `PUB_CACHE` unchanged. Actual offline probes confirmed that a relative value resolves from pub's working directory and a defined empty value selects that directory, which is `src/desktop` in this build. An undefined value selects the default cache. |
| Generator scope | Pinned [`commands/create.dart`](https://github.com/flutter/flutter/blob/c197ca5199e9ee5661e865596c9c07294dfab51c/packages/flutter_tools/lib/src/commands/create.dart) gates both pub restoration and platform tooling refresh behind `shouldCallPubGet`. Therefore `flutter create --no-pub --platforms=windows` can generate runner files on another host without compiling or requiring Windows plugin-link privilege. Its generated lock still needs restoration. |
| Windows Script Host | Microsoft's [`wscript` contract](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wscript) documents batch mode and the script time limit. Its [VBScript feature guidance](https://techcommunity.microsoft.com/blog/windows-itpro-blog/vbscript-deprecation-timelines-and-next-steps/4148301) establishes that the engine can be absent even when the host executable exists. The preflight therefore uses a disposable `WScript.Quit 17` script with a time bound; it does not register a task or alter the optional feature. |

A successful local symbolic-link probe establishes capability for the tested
source location and targets. It does not certify all future package-cache paths,
downloads, plugin compilation or native startup. Those later stages must keep
their original failures visible. `flutter doctor` is not an all-purpose boolean:
the pinned command has no `--machine` flag, and unrelated Android findings do not
describe Windows readiness. The separate read-only `flutter config --machine`
operation reports configuration.

## Findings at the new baseline

| Finding | Concrete route | Required correction |
| --- | --- | --- |
| D1: Missing prerequisite gate | The normal source launcher checked executable names, then reached plugin-link creation without checking actual link ability. The same missing prerequisite was already recorded in the 11 November Windows ledger. | One shared full preflight for source launcher, direct builder and review; preserve distinct capability failures. The standalone generator checks its pinned SDK and preserves the lock without claiming native readiness. |
| D2: Failure detail hidden by stage wrapper | `pub get` output explained the link error, but builder/review added only `Flutter dependencies failed`. Other stages used similarly generic wrappers. | Name the failed stage, retain its output and exit status, and stop before compilation/package launch. |
| D3: Present executable mistaken for compatible toolchain | An older Flutter/Dart, old Git, unsupported PowerShell, missing CMake/SDK or incomplete Visual Studio can pass the old command lookup. | Check the declared versions and relevant Windows toolchain capability; report the exact unmet requirement. |
| D4: Late path/architecture failure | Flutter rejects specific project characters and chooses ARM64 on an ARM64 host; Continuum expected x64 output unconditionally. | Apply the actual Flutter path rule and the product's x64 contract before expensive work. |
| D5: Test backend can differ from built source | An inherited `CODEX_SCHEDULER_SOURCE` can direct a Windows adapter test to another checkout. | Pin tests to the candidate root and restore the caller's environment in `finally`; preserve deliberate runtime overrides separately. |
| D6: Runtime PowerShell discovery differs from launcher | Launcher discovery and the application/worker's hardcoded standard path can select different installations or fail after a successful source build. | Align supported PowerShell resolution and preserve explicit errors across Dart, bridge, Shared and worker launch surfaces. |

Corrections and test results are recorded only after implementation review. These
findings are not clean-pass credits.

During implementation, independent review found **D7** in the first shared process
helper: its output cap was checked after `ReadLineAsync` completed. An actual
PowerShell child wrote and flushed 17 MiB without a newline; the nominal 16 MiB
limit did not stop it before the two-second deadline. A fixed-size read and an
aggregate per-chunk cap are required. This was found before freeze and contributes
no clean-pass credit.

Independent review then reproduced **D8** in the first preflight JSON reader:
PowerShell's default JSON array enumeration turned `[]` into null and `[{}]`
into a hashtable. The Visual Studio detector expected an array, so an ordinary
single installation or an empty first workload query could never proceed.
The reader must preserve zero-, one- and many-element arrays, with a regression
that follows the empty IDE query through to a valid Build Tools result.

**D9** concerned process lifetime after the direct tool exited. A real child
fixture left a descendant's heartbeat running after the parent's one-second
timeout because inherited pipes remained open and cleanup skipped an already
exited root process. Windows [Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
and [`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_limit_information)
provide an operating-system process-group lifetime contract. The implementation
must establish containment before allowing a tool to spawn, retain bounded
output reads and verify descendant cleanup; portable process-group checks do
not establish Windows Job Object execution on this Linux host.

**D10** affected packaging from a valid source path containing square brackets.
An actual fixture at `checkout[review]/Release` contained the expected executable,
but the builder's `Copy-Item -Path <release>/*` returned without error and copied
no files because PowerShell treated the brackets as wildcard syntax. Flutter's
Windows path restriction permits brackets. Release children must be enumerated
and copied by literal path, with spaces/brackets covered by regression. The
Windows drive-root output cleanup comparisons also require consistent parent
normalization; a permitted root output must not fail its own cleanup guard.

**D11** was reached by an actual worker/subprocess lifecycle fixture. The npm
background entry argument was assigned from a conditional whose one-element
array became a scalar. Native argument splatting then split the JavaScript
entry path, and Node attempted to load `/` as its module. Capturing the whole
conditional in an array preserves the entrypoint as one argument. The fixture
uses a mock App Server and disposable state, without a real account or Windows
task registration.

**D12** was reproduced in the archive writer: a source containing visible and
hidden files was compressed successfully, but the extracted ZIP omitted the
hidden file. Microsoft's [Compress-Archive documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.archive/compress-archive)
explicitly describes that behavior and recommends the .NET API to include
hidden entries. Because the manifest includes hidden files, the old writer
could not satisfy its own extracted-package check. Archive regression must use
the production writer and inspect actual extracted bytes, including existing
output preservation.

**D13** was caught by the actual bundled-Dart prerequisite fixture: a typed
PowerShell string parameter converted an absent `FLUTTER_WINDOWS` into an empty
string. Flutter interprets a defined non-`true` value as disabled, so this wrongly
blocked an ordinary unset environment. Absence and explicit empty values must
remain distinct for both this feature flag and `PUB_CACHE`.

The genuine Flutter runner fixture exposed **D14**: positional `Push-Location`
treated a supported bracketed project path as wildcard syntax. The generator
and review entrypoint now use `-LiteralPath`; the fixture runs the actual pinned
Flutter SDK from a bracketed/Unicode source directory.

**D15** concerned overlapping runner generation. A second invocation could read
the first invocation's temporary SDK-only dependency lock and restore it over
the reviewed application lock. The generator now takes an exclusive file handle
before reading or mutating that lock. A real held-handle regression verifies
rejection without changing the lock, and a failed tool process verifies exact
restoration. The handle is released in `finally`; file presence is not treated
as an active lease. This protects generation only, not the entire build pipeline.

The first frozen review attempt found **D16** in the documented direct-EXE
entrypoint. Release-mode source discovery disabled working-directory search,
but still walked upward from the executable. An incomplete package inside an
unrelated checkout could therefore load that parent's backend and bridge. The
normal package launcher rejected the incomplete package; directly opening the
EXE still reached the fallback. A filesystem regression reproduced the release
resolver selecting the unrelated parent. A release must use its own adjacent
backend and bridge unless an explicit override is supplied; ancestor search is
only a development-mode convenience.

The same review found **D17** in an explicit relative
`CODEX_SCHEDULER_SOURCE`. The old resolver returned the original relative text
after checking only the worker file. The adapter then used that text both in the
bridge argument and as the subprocess working directory, effectively repeating
the relative prefix. Source selection must preserve the override's caller-CWD
meaning, resolve it once to an absolute directory, require both backend and
bridge, and use that single path for subsequent execution. The normal launcher
starts the app in its package directory. An invalid explicit override must fail
explicitly.

Both findings invalidated the first frozen attempt at digest
`719c127dfd819939fb55a2da22b48378d977e40fce302b8ffd94db22aa3b51e8`.
Its passing tests and unchanged digest earned no clean round. The streak reset
to **zero**; the corrected inputs were then frozen and the complete matrix was
repeated for the three credited rounds below.

## End-to-end route matrix

Every clean round must revisit all rows. A route can be verified by source and
portable injected failures without claiming that its Windows operation ran.

| Route | Required adverse cases and invariant |
| --- | --- |
| Root `.cmd` → launcher | Missing/unsupported PowerShell, quoted paths and nonzero child exit remain visible; no silent use of another application. |
| Folder classification | Complete source ZIP/checkout/worktree, source plus stray EXE, runtime package, partial source/runtime and pinned fallback retain their intended distinct routes. The fallback requires the supplied verifier; two copied launcher files alone fail explicitly. |
| Source trust and prerequisites | Required scripts are present; linked/reparse script paths are not unblocked; tool versions, x64, actual link capability, source path and harmless WSH/VBScript execution are checked without changing OS policy. Independent unmet prerequisites are reported together; dependent unrun checks are identified explicitly. |
| Direct build/review entry | Direct compilation/review invokes the shared full prerequisite contract; caller environment and current directory are restored after failure. |
| Standalone runner generation | The pinned SDK is checked before `create --no-pub`; literal paths preserve valid bracketed/Unicode directories; an exclusive handle precedes the lock snapshot; the committed dependency lock and caller directory are restored after a failed create; icon installation follows successful generation and its errors propagate. This operation alone performs no pub restoration, native compilation or launch. |
| Dependency restore | Enforced lock, offline/network/package errors and each link-error class retain precise stage output; no fake success or SDK mutation. |
| Analysis/tests/compilation | Stages run in order against the candidate backend; any failure prevents later stages and launch. Test success is not compilation success. |
| Runtime packaging | Backend/bridge/component import closure, DLL/data payload, icon and source identity are present; a source archive cannot inherit a parent repository's SHA. |
| Manifest/ZIP | Missing, modified, duplicate, escaping and linked entries fail; actual extracted content is verified; existing output is preserved and cleanup stays inside this operation's staging area. |
| Package/cache launch | Complete local packages and a cached/downloaded pinned release are validated consistently; failure never falls through to a different build. Direct release-EXE launch also requires its adjacent backend and bridge and cannot borrow a parent checkout. Executable/backend identity is visible. |
| App → PowerShell → Node/Codex/Git | Supported runtime resolution, absolute validated source selection, stream completion/timeouts, errors, exact conversation identity, saved associations and long-record discovery remain covered by the actual subprocess regressions. Explicit overrides require both backend and bridge and fail on invalid input. |
| Schedule/worker surfaces | Runtime file allowlists and Background/Native/Shared launch arguments retain their dependencies and mode boundaries. Fixture execution must not become a live scheduled task or model turn. |

## Three-consecutive-pass protocol

1. Freeze a path/content digest of all production, build, test, lock and ordinary
   documentation inputs. Record SDK/tool identities. Exclude only this audit log
   and generated result logs so recording a result cannot change its own digest.
2. Each round independently walks every route above. Reviewers emphasize
   different failure assumptions, but no round omits the full matrix. Run the
   applicable adverse checks against the frozen digest and record their logs.
3. A new defect, unresolved finding, or production/test/input change resets the
   clean streak to zero. Correct it, freeze a new digest and start again. A repeat
   of only the changed helper's tests is not a complete round.
4. Count a round only after every reviewer reports no new issue and all applicable
   checks have their actual result. Record skips and environment limitations;
   previous PR results and unrelated green tests do not close a current route.
5. Three clean rounds establish the reviewed source/portable verification scope.
   They do not turn an unavailable Windows build, GUI, Task Scheduler or account
   test into native acceptance.

| Round | Frozen input digest | Result | Consecutive clean rounds |
| --- | --- | --- | --- |
| Baseline investigation | `ab94244d260cd02c66989620307c62e2ec206ab2` | Findings D1–D6; corrected before the first freeze | 0 |
| First frozen attempt | `719c127dfd819939fb55a2da22b48378d977e40fce302b8ffd94db22aa3b51e8` | Unclean: D16/D17 reproduced; no credited round | 0 |
| 1 | `7e6da4e0d26ade9b267d9a8a5251fb980e5696e7126e9175aae165b38f866ecf` | Clean within source/portable scope: root gates and all three independent full-matrix reviews completed with no new issue; native Windows remains unobserved | 1 |
| 2 | `7e6da4e0d26ade9b267d9a8a5251fb980e5696e7126e9175aae165b38f866ecf` | Clean within source/portable scope: repeated root gates and all three independent full-matrix reviews found no new issue | 2 |
| Interrupted third-round attempt | `7e6da4e0d26ade9b267d9a8a5251fb980e5696e7126e9175aae165b38f866ecf` | Execution environment interrupted verification sessions; partial evidence retained without credit. No input change or new product finding was established | 2 |
| 3 | `7e6da4e0d26ade9b267d9a8a5251fb980e5696e7126e9175aae165b38f866ecf` | Clean complete rerun: root gates and all three independent full-matrix reviews completed with no new issue | 3 |

## Frozen inputs and completed verification

The canonical digest is SHA-256 of a compact, key-sorted JSON array of records
`{path, mode, blob}`, ordered by repository-relative path. `blob` is the result
of `git hash-object --path=<path> <path>`, so repository attributes and Git's
content normalization apply; `mode` is captured from the Git index at freeze.
The path set includes tracked and nonignored untracked inputs. Before and after
each completed round, the path set and content hashes were recomputed. This is
a source-input digest, not a Git commit ID or a Windows executable checksum.

Only this audit ledger is excluded among ordinary repository documents.
Generated ignored outputs and result logs outside the repository are also
excluded. Production files, tests, dependency locks and all other ordinary docs
remain in the 263-file manifest. The interrupted third-round attempt made no
input change; its partial logs were retained and a complete rerun supplied the
third credit.

| Tool | Actual verification environment |
| --- | --- |
| Host | Linux x86_64 |
| PowerShell | 7.4.0 and 7.7.0; the root gate used 7.7.0 in rounds 1/3 and 7.4.0 in round 2 |
| Flutter / Dart | Flutter 3.47.9 / Dart 3.13.7, with the pinned revisions recorded above |
| Node / npm | Node v24.22.3 / npm 11.9.0 |
| Git | 2.52.0 |

The following results apply **in each of the three completed rounds**; repeated
runs are not added together to inflate the case counts. All five helper suites
in the first five rows ran on both PowerShell versions in every round.

| Gate | Result per completed round |
| --- | --- |
| Windows prerequisites, including real bundled-Dart probes and inherited StrictMode | 26 passed on 7.4; 26 passed on 7.7; no skips |
| Portable launcher decisions/trust | 15 passed on each PowerShell version; no skips |
| Actual build-process/stage regressions | 14 passed on each PowerShell version |
| Complete package/production ZIP/extracted bridge/exact original artifact | 27 passed on each PowerShell version; synthetic current native binaries are inert fixtures |
| Package paths/hidden/Unicode/bracketed archive bytes | 10 passed on each PowerShell version |
| Flutter regression suite | 142 passed; 2 explicit native Windows skips; `visual-capture` intentionally excluded |
| Flutter analyzer and Dart/JavaScript format checks | Passed |
| Node portable selection | 85 passed; the 3 environment-blocked socket cases below were excluded, not counted as passes or runner skips |
| Repository evidence | 27 passed |
| Source identity / selected PowerShell / genuine Flutter generator | 7 / 5 / 3 passed, respectively; generator success is not compilation success |
| Actual JSON bridge, pinned worker, quota lifecycle/policy, source and preview metadata gates | Passed with disposable state and mock account/App Server responses |
| Native Windows launcher / Windows Script Host integration | Explicitly skipped on Linux |
| Documentation links | 37 Markdown files, 215 relative links, zero errors |
| PowerShell syntax | All 130 frozen `.ps1`/`.psm1`/`.psd1` files and the CMD bootstrap's embedded PowerShell parsed on 7.4 |

The root orchestration completed 15 exit-zero commands in each round, including
the explicit Windows Script Host skip. The independent helper results above
supplement that orchestration; an exit-zero skip is not a native pass.

### Reproduction commands and evidence

Use an isolated test shell with the pinned tools. Set `CONTINUUM_TEST_FLUTTER_SDK`
to the Flutter 3.47.9 SDK directory, `CONTINUUM_TEST_FLUTTER` to its executable,
`CONTINUUM_TEST_PWSH` to the selected absolute PowerShell executable, and
`CODEX_SCHEDULER_SOURCE` to the candidate repository root. Repeat the helper
commands with PowerShell 7.4.0 and 7.7.0:

```powershell
pwsh -NoLogo -NoProfile -Command "Set-StrictMode -Version Latest; & ./tests/windows-build-prerequisites.test.ps1"
pwsh -NoLogo -NoProfile -File tests/root-launcher-decision.test.ps1
pwsh -NoLogo -NoProfile -File tests/flutter-build-process.test.ps1
pwsh -NoLogo -NoProfile -File tests/flutter-package-paths.test.ps1
pwsh -NoLogo -NoProfile -File tests/flutter-preview-package.test.ps1 -PinnedPreviewDirectory '<verified original Preview 1 directory>'
npm run check:docs
npm run format:check
```

The root PowerShell suites use the same `-NoLogo -NoProfile -File` invocation:
`flutter-port-source`, `flutter-preview-metadata`,
`flutter-preview-source-identity`, `powershell-host-selection`,
`session-repository-evidence`, `repository-bridge-flow`,
`codex-worker-integration`, `quota-continuation-lifecycle`, `quota-continuation`,
`flutter-runner-generation` and `windows-task-host` under `tests/*.test.ps1`.
The Linux quota-policy child receives a disposable `WINDIR` value for its mocked
task-action path; it does not register a Windows task. From `src/desktop`, run:

```text
dart format --output=none --set-exit-if-changed lib test
flutter --suppress-analytics analyze --no-pub
flutter --suppress-analytics test --no-pub --exclude-tags visual-capture --reporter expanded
```

Node's frozen portable selection runs every `tests/*.test.js` and
`tests/*.test.mjs` with `node --test`, excluding exactly these names using
`--test-skip-pattern`:

- `native credentials are private, require active owner, and never fork the thread`
- `owner closes promptly even if a native terminal lease is still connected`
- `one App Server process, two viewers, command approval and user question`

The full unfiltered integration run recorded 85/88 passes: Unix-socket `EPERM`
and two dependent mock-owner timeouts blocked those three cases. They remain
unverified on this host; excluding them does not repair or certify that route.

The local evidence set is `runtime-investigation/windows-delivery/`, outside the
repository. It retains `frozen-inputs.json`, exact command/result JSON, complete
command logs and each reviewer's full route walk. The credited folders are
`round-1`, `round-2` and `round-3-final`. `attempt-1/round-1` preserves the failed
freeze and D16/D17 reproduction; `round-3` preserves the interrupted, uncredited
attempt. The exact original preview ZIP and manifest were independently checked;
current fixture package tests execute the extracted PowerShell bridge, not the
inert Windows EXE.

## Scope of this documentation review

The current README, setup, troubleshooting, architecture, release policy,
security/privacy, current-state and Windows acceptance guides, desktop developer
guide and tests guide were reread in full. Relevant builder, review, runner,
launcher, lock, source-identity and source-integrity code was inspected alongside
the pinned Flutter implementation. The previous [repository investigation](REPOSITORY-DISCOVERY.md)
retains its own dated evidence; it is not counted as a clean round here.

The full Node run during integration reported **85 passes out of 88 tests**.
Three Shared-session tests remained blocked on this host: Unix-socket `EPERM`
and two mock-owner timeouts. That is not an all-green Node result. An exploratory
Flutter run without the repository's `--exclude-tags visual-capture` option also
failed six capture cases because their intentionally absent capture PNGs were
required. Those results are retained; no replacement golden images were invented.
The documented production Flutter gate and completed frozen-round results are
recorded separately above.

No current native Windows build or launch is claimed. Developer Mode or an
equivalent permitted symbolic-link capability still has to exist on the Windows
build machine. The preflight can detect and explain that state; it cannot enable
an unavailable privilege itself.

Native Windows C++ compilation, the generated EXE/GUI, Windows Job Object
execution, CMD/WSH integration, Task Scheduler and real account/model activity
were not exercised by these Linux rounds. The three clean rounds establish the
documented source and portable verification scope, with those limits intact.
