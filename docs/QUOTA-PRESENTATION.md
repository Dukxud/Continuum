# Quota window presentation

**Merged in PR #22; project paused.** See [current evidence](CURRENT-STATE.md). This is the same implementation for **Plus and Pro**, not a Pro-only patch and not a subscription entitlement table.

## Contract

`CodexUsage.js` selects the applicable model bucket, derives each window label from `windowDurationMins`, and omits absent primary/secondary windows. `SchedulerController.quotaWindows` supplies that normalized data to Full, Monitor and Micro. Presentation does not call a plan-tier switch.

| Returned windows | All three views show |
| --- | --- |
| Five-hour and Weekly | Two rows/cards, each with its own percentage/reset |
| Weekly only, in either source slot | One WEEKLY row/card; no false five-hour label or phantom second row |
| Five-hour only | One 5-HOUR row/card |
| Another reported duration/label | That label; never inferred from plan name or reset date |
| Missing or blank label | Neutral `Usage` |
| No returned windows | `No usage windows reported` |
| Failed read | A single unavailable message; a successful refresh restores returned data |

Weekly styling follows the Weekly label, not array position. Ordinary palette styling for another window does not rename it. Window label, remaining percentage and reset always travel together. Micro retains its actual reset timestamp and exhausted-window countdown; labels fit within the compact row with a tooltip. Native window dimensions are unchanged; this patch removes fabricated rows but does not implement automatic one-row window resizing.

## Boundaries

The response describes current account/model data, not a promise that every Plus or Pro subscription has a specific set of limits. No tier-specific rule, account permission, model bucket attribution, quota permissions, scheduled execution, retry rules, native window dimensions or the accepted Windows icon changed. A displayed reset is not proof usage is authorized. Do not infer unlimited use from an absent window or unknown value.

## Verification

`flutter_port/test/quota_windows_test.dart` has 23 in-memory-adapter widget cases: weekly-only, five-hour-only, both windows in both orders, unfamiliar/blank labels, empty data, two-to-one refresh, unavailable/recovery, view switching without extra reads and weekly exhaustion countdown. It never starts Codex or registers a task.

Windows run [42327638037](https://github.com/Dukxud/codex-resume-scheduler/actions/runs/42327638037) passed on `796f25e757412a8cabc3fa68531405ffc1b6a21b`; BP211 packages that candidate. PR #22 merged at `f83b11bc3acb9f0447b41d0a7b7d414bd86364ff` with the same source tree. The owner authorized merge and a project pause; live BP211 visual confirmation remains unrecorded.

On a future native review, use the same account/model while switching Full/Monitor/Micro; confirm the labels, number of rows, percentages and resets agree. No task needs to be scheduled for that display check.
