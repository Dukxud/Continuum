# Flutter parity acceptance — Windows v1.16 baseline

The accepted main-branch WinForms Scheduler v1.16.0 is the source of truth.
This Flutter candidate is an alternate UI, not a new scheduler engine.
The Windows bridge invokes the existing verification, pinned-runtime,
Task Scheduler, history and worker functions; this is not a backend rewrite.

## Requirements and evidence

| V1.16 behavior | Flutter implementation | Acceptance |
| --- | --- | --- |
| CLI conversations, model/effort/access | Live bridge to original data/Codex catalog | Windows manual pending |
| Repository discovery, alternatives and explicit Browse | Bridge resolution + conflict UI | Windows manual pending |
| Manual time, minus/plus, Now+2, reset+2 | Flutter controls, server checks before scheduling | Windows manual pending |
| Live model-specific 5-hour/weekly usage | Official CodexUsage.js, no estimated quota | Windows manual pending |
| Full run form and compact next-run view | Flutter, separate desktop window sizing | Window test added; Windows visual pending |
| No upcoming-run message in compact mode | Hide next-run area when no task | Widget covered |
| Distinct countdown progress / running state | Native renderer with original working mode | Visual pending |
| Approved Windows v1.8 pixels and v3 Aero Liquid optical GLSL | Exact source PNGs; mechanically adapted original fragment shader | Source byte/hash checked; GPU visual pending |
| Rounded partial droplet; square full tip | Original GLSL cap contract retained | Visual pending |
| Independent 5-hour / weekly / countdown / working colors | Same v1.16 barAppearance schema | Unit tested; visual pending |
| Custom RGB, glass/enamel/pearl, studio modes, shimmer, speed, toggle | Two-tab appearance editor with live preview, automatic persistence, Defaults/Done; no explicit Save | Unit/widget coverage; Windows visual pending |
| Pinned runtime and one-time task registration | Existing PowerShell RuntimeBundle + OneTimeTasks | Source checked; real task pending |
| Workspace identity, model/effort, quota, branch and overlap checks | Existing worker plus server-side registration preflight | Real task pending |
| Cancellation before worker starts, never cancels running process | Original OneTimeTasks with post-cancel reconciliation | Real task pending |
| Upcoming and recently completed/legacy Windows results | Task Scheduler + saved JobOutcomes | Windows manual pending |
| Detailed history: result, time, exit code, attempt, next task, message | Flutter history dialog, response and worker transcript | Windows manual pending |
| Copy response / copy worker log / remove from history (non-destructive) | Flutter dialog / bridge | Windows manual pending |
| Autosaved draft and appearance | Original v1.16 settings schema; appearance changes now persist live with final close flush | Source and unit checks; Windows manual pending |
| No terminal after launch | Native Flutter Windows executable in local unsigned preview bundle | Windows manual pending |
| Mac, Linux and web execution | Not implemented: independent platform adapters needed | Out of Windows-port scope |

## Visual acceptance baseline (WinForms v1.16)

Flutter must reproduce the visible UI, not merely the behavior or GLSL source.
The accepted Windows sources are `CodexUiForms.ps1`,
`CodexUiPixelTheme.ps1`, `CodexDashboard.ps1`,
`CodexBarAppearance.ps1` and `assets/AeroBar.html`.

- Full view: 920 logical-pixel client layout, Segoe UI, five tinted stepped
  pixel bands at y=54/102/148/194/238; labels and inputs at their original
  x coordinates; two 428×108 usage cards at (18,358) and (470,358).
- Compact view: 464-pixel client width; 5-hour and weekly meters **stacked**
  with 117 pixels between card starts, not squeezed side by side; bottom
  actions right aligned. No task means 391-pixel client height, one upcoming
  task means approximately 572 pixels.
- Appearance: the accepted WinForms editor was 566×752 with all controls on
  one page. Following native BP152 feedback, Flutter intentionally uses a
  566×514 two-tab editor: Colors has all four selectors and full-height
  preview; Optics has material, lighting, both sliders, optical toggle and
  a live four-bar compact preview. Defaults and Done remain visible in the
  ordinary full window without scrolling. Settings auto-save as changed;
  closing the editor flushes the pending write, including Escape and backdrop.
- Aero: original GL shader and PNG sources are necessary but not sufficient.
  Check pixel composition, optical reflectance, softened terminal columns,
  partial rounded cap, full square cap, custom RGB and animation against
  the approved v1.16 actual Windows rendering at the **same DPI and usage**.
- Confirm there are no repeated accessibility-tree errors, without disabling
  platform accessibility as a workaround. Distinguish any Flutter engine issue
  from UI-specific semantics churn by reproducing with a minimal case.

Native BP152 screenshots confirmed the geometry-based main layout and exposed
three editor/window issues: clipped controls, explicit Save friction, and
stale full-mode sizes. The current draft corrects these in source, but the
revised two-tab editor, auto-save, and serialized native sizing are **not
accepted** until exact-head Windows CI and renewed BLACK-PUDDLE inspection.

## Conditions for acceptance

1. Run a single bounded source-integrity, Dart analyzer and widget/unit-test pass with Run-WindowsReview.ps1 on BLACK-PUDDLE. Stop on any failure; no automatic retries or unbounded CI.
2. Compare full and compact Flutter windows directly to accepted v1.16. Verify exact content-fit size after repeated switches, the original Aero optics, all controls on both appearance tabs, custom RGB, Defaults, and persistence after Done, Escape, and outside close. No scrolling or hidden controls.
3. Schedule **one safe read-only** test run in a disposable Git repository and a verified CLI session. Read the actual worker result and evidence; Task Scheduler exit 0 alone is insufficient.
4. Schedule and cancel a separate future run. Verify the Windows task is unregistered, the cancelled outcome is visible, and no worker was started.
5. Inspect model/effort, workspace verification and quota fail-closed behavior, conflicting repository hints, near-past times, and user-preserved settings.
6. Independently review the changed bridge/UI for safety, clean code, no duplicate worker rules and reliable process exit handling.
7. **Do not merge or publish** until these gates pass on the actual Windows machine. The WinForms v1.16 app remains authoritative and usable.

## Windows commands

From a checkout of feat/flutter-windows-review-v0:

    pwsh -NoProfile -STA -File .\flutter_port\Run-WindowsReview.ps1

After acceptance, create a standalone unsigned local archive (never publish it):

    pwsh -NoProfile -STA -File .\flutter_port\Build-WindowsPreview.ps1

The release archive bundles the Flutter executable and the original worker;
it does not change Task Scheduler jobs created by the existing GUI. It is
**unsigned**, requires existing PowerShell 7, Node, Git and npm Codex, and
makes no antivirus-exclusion or signing-bypass changes.

The Flutter interface and original fragment program are portable assets.
The only current scheduler adapter is Windows. A macOS, Linux or web product
requires explicit platform worker/scheduler adapters and independent acceptance.

## Accessibility root cause and mitigation

The appearance dialog contains two Material sliders in a pushed modal route.
Flutter issue [#190357](https://github.com/flutter/flutter/issues/190357)
reproduces a Windows `ui::AXTree` orphan-node failure with precisely this
combination; reports include accessibility-tree freezes. The documented
mitigation wraps each slider in its own `Overlay.wrap(alwaysSizeToContent:
true, clipBehavior: Clip.none, child: Slider(...))`, retaining keyboard and
screen-reader slider semantics. This mitigation is now applied and widget
coverage checks the two local overlays. It does **not** establish that all
AXTree errors are fixed: tooltip/list errors and engine null-parent crashes
remain separate upstream concerns; native Windows accessibility acceptance
is mandatory. See [Flutter API](https://api.flutter.dev/flutter/widgets/Overlay/wrap.html)
and [Flutter issue #182444](https://github.com/flutter/flutter/issues/182444).
