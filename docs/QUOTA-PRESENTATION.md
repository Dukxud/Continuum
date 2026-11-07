# Quota window presentation

## Contract

The Flutter Full, Monitor and Micro views display the normalized `windows` returned by `CodexUsage.js`. That reader derives each `label` from `windowDurationMins` and removes absent primary/secondary windows. A list position is not a duration: the first returned window can be Weekly.

- Render one row/card per returned window, preserving its label, remaining percentage and reset timestamp together.
- Do not hard-code a five-hour first row or weekly second row, and do not create a placeholder for an absent window.
- Weekly appearance follows the `Weekly` label, not the row position. Other labels retain the ordinary quota palette. This chooses presentation only; it does not change any account permissions or limits.
- Preserve unfamiliar duration labels. A missing/empty label is shown neutrally as `Usage`, never guessed from subscription tier, list index or reset date.
- No returned windows: show `No usage windows reported`. An unavailable read has one unavailable message, not two fabricated limits. A later successful refresh restores the actual windows.
- Micro retains the reported reset timestamp and exhaustion countdown for the corresponding window, including a lone Weekly window.

This is a presentation correction. Account/workspace checks, model bucket attribution, quota permissions, scheduled execution, retry rules, native window dimensions and the accepted Windows icon are unchanged. No subscription-specific rule is encoded.

## Regression coverage

`flutter_port/test/quota_windows_test.dart` uses an in-memory adapter; it never launches Codex or registers a Windows task. It covers weekly-only, five-hour-only, both windows in both orders, unknown/missing labels, empty data, two-to-one refresh transitions, failure/recovery, view switching and a weekly-only exhausted countdown. Existing missing-data assertions now require a neutral state rather than synthetic cards.

## Native review

On the exact built preview, open Micro with the current account. When Codex returns one Weekly window, expect one `WEEKLY` row with its current remaining percentage/reset and no `5-HOUR` row or second empty bar. Switch Full/Monitor/Micro and confirm the same data. This checks display behavior without scheduling a Codex turn. CI uses fixtures and cannot certify the operator's current live account response.
