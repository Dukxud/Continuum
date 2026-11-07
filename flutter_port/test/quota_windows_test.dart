import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/aero_bar.dart';
import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/date_labels.dart';
import 'package:codex_resume_flutter/main.dart';
import 'package:codex_resume_flutter/scheduler_controller.dart';

/// Local fixture only: these tests never invoke Codex or Task Scheduler.
class QuotaFixtureAdapter implements SchedulerAdapter {
  QuotaFixtureAdapter(this.mode, this.windows);
  final String mode;
  List<Map<String, dynamic>> windows;
  bool failUsage = false;
  int usageReads = 0;

  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    switch (action) {
      case 'load':
        return {
          'sessions': [], 'pending': [], 'history': [],
          'settings': {
            'compactMode': mode != 'Full', 'microMode': mode == 'Micro',
            'draft': {},
          },
        };
      case 'usage':
        usageReads++;
        if (failUsage) throw SchedulerException('Fixture usage unavailable');
        return {
          'ok': true, 'model': 'quota-fixture',
          'models': [
            {'id': 'quota-fixture', 'efforts': ['medium'],
             'defaultEffort': 'medium', 'isDefault': true},
          ],
          'windows': windows.map((w) => Map<String, dynamic>.from(w)).toList(),
          'accountId': 'workspace-sha256:' + 'a' * 64,
          'ordinaryUsageAllowed': true,
        };
      case 'pending':
        return {'pending': [], 'history': []};
      case 'save':
        return {'saved': true};
      default:
        throw StateError('Unexpected adapter action: $action');
    }
  }
}

Size viewSize(String mode) => switch (mode) {
  'Micro' => const Size(392, 212),
  'Monitor' => const Size(540, 535),
  _ => const Size(1240, 850),
};

Map<String, dynamic> window(String label, double remaining,
    {int? reset}) => {
  'label': label, 'remainingPercent': remaining,
  if (reset != null) 'resetsAt': reset,
};

Future<SchedulerController> openFixture(WidgetTester tester,
    QuotaFixtureAdapter adapter) async {
  tester.view.physicalSize = viewSize(adapter.mode);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    home: SchedulerHome(adapter: adapter)));
  // Aero animation is intentional: use bounded pumps, never pumpAndSettle.
  await tester.pump(const Duration(milliseconds: 200));
  expect(tester.takeException(), isNull);
  return (tester.state(find.byType(SchedulerHome)) as dynamic).controller
    as SchedulerController;
}

Finder quotaRow(String mode, int index) => find.byKey(Key(
  mode == 'Micro' ? 'micro-window-$index' : 'capacity-window-$index'));

void expectWindow(WidgetTester tester, String mode, int index,
    String label, double remaining, String kind) {
  final row = quotaRow(mode, index);
  expect(row, findsOneWidget);
  expect(find.descendant(of: row, matching: find.text(label.toUpperCase())),
    findsOneWidget);
  expect(find.descendant(of: row,
    matching: find.text('${remaining.toStringAsFixed(1)}%')), findsOneWidget);
  final bar = tester.widget<AeroLiquidBar>(find.descendant(
    of: row, matching: find.byType(AeroLiquidBar)));
  expect(bar.kind, kind);
  expect(bar.amount, remaining);
}

void main() {
  for (final mode in ['Full', 'Monitor', 'Micro']) {
    testWidgets('$mode weekly-only response never appears as five-hour',
        (tester) async {
      final reset = DateTime.now().add(const Duration(days: 7))
        .millisecondsSinceEpoch ~/ 1000;
      await openFixture(tester, QuotaFixtureAdapter(mode,
        [window('Weekly', 90, reset: reset)]));
      expectWindow(tester, mode, 0, 'Weekly', 90, 'weekly');
      expect(quotaRow(mode, 1), findsNothing);
      expect(find.text('5-HOUR'), findsNothing);
      expect(find.text('FIVE-HOUR'), findsNothing);
      expect(find.textContaining('UNAVAILABLE'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$mode five-hour-only response has no synthetic weekly row',
        (tester) async {
      await openFixture(tester, QuotaFixtureAdapter(mode,
        [window('5-hour', 35)]));
      expectWindow(tester, mode, 0, '5-hour', 35, 'quota');
      expect(quotaRow(mode, 1), findsNothing);
      expect(find.text('WEEKLY'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final reversed in [false, true]) {
      testWidgets('$mode preserves label/value/reset pairing (reversed=$reversed)',
          (tester) async {
        final now = DateTime.now();
        final shortReset = now.add(const Duration(hours: 3))
          .millisecondsSinceEpoch ~/ 1000;
        final weeklyReset = now.add(const Duration(days: 7))
          .millisecondsSinceEpoch ~/ 1000;
        final windows = [
          window('5-hour', 25, reset: shortReset),
          window('Weekly', 90, reset: weeklyReset),
        ];
        await openFixture(tester, QuotaFixtureAdapter(mode,
          reversed ? windows.reversed.toList() : windows));
        expectWindow(tester, mode, reversed ? 1 : 0, '5-hour', 25, 'quota');
        expectWindow(tester, mode, reversed ? 0 : 1, 'Weekly', 90, 'weekly');
        final formatter = mode == 'Micro'
          ? (DateTime at) => 'RESETS ${formatDayMonth(at)} · ${formatLocalClock(at)}'
          : (DateTime at) => 'Resets ${formatLocalDateTime(at)}';
        for (final (index, reset) in [
          (reversed ? 1 : 0, shortReset),
          (reversed ? 0 : 1, weeklyReset),
        ]) {
          final text = formatter(DateTime.fromMillisecondsSinceEpoch(reset * 1000));
          expect(find.descendant(of: quotaRow(mode, index),
            matching: find.text(text)), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$mode preserves unfamiliar durations and uses neutral missing label',
        (tester) async {
      await openFixture(tester, QuotaFixtureAdapter(mode,
        [window('60-minute', 65), window('', 40)]));
      expectWindow(tester, mode, 0, '60-minute', 65, 'quota');
      expectWindow(tester, mode, 1, 'Usage', 40, 'quota');
      expect(find.text('5-HOUR'), findsNothing);
      expect(find.text('WEEKLY'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$mode no reported windows is not a pair of invented limits',
        (tester) async {
      await openFixture(tester, QuotaFixtureAdapter(mode, []));
      expect(find.text('No usage windows reported'), findsOneWidget);
      expect(find.byType(AeroLiquidBar), findsNothing);
      expect(find.text('5-HOUR'), findsNothing);
      expect(find.text('WEEKLY'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$mode refresh removes obsolete windows and recovers from failed usage',
        (tester) async {
      final adapter = QuotaFixtureAdapter(mode,
        [window('5-hour', 25), window('Weekly', 90)]);
      final controller = await openFixture(tester, adapter);
      expectWindow(tester, mode, 0, '5-hour', 25, 'quota');
      adapter.windows = [window('Weekly', 88)];
      await controller.readUsage();
      await tester.pump(const Duration(milliseconds: 200));
      expectWindow(tester, mode, 0, 'Weekly', 88, 'weekly');
      expect(quotaRow(mode, 1), findsNothing);
      expect(find.text('5-HOUR'), findsNothing);
      adapter.failUsage = true;
      await controller.readUsage();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Usage unavailable · automatic retry'), findsOneWidget);
      expect(find.text('WEEKLY'), findsNothing);
      expect(find.byType(AeroLiquidBar), findsNothing);
      adapter.failUsage = false;
      await controller.readUsage();
      await tester.pump(const Duration(milliseconds: 200));
      expectWindow(tester, mode, 0, 'Weekly', 88, 'weekly');
      expect(find.byKey(const Key('quota-empty-state')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Micro weekly-only exhaustion keeps its own reset countdown',
      (tester) async {
    final reset = DateTime.now().add(const Duration(days: 5))
      .millisecondsSinceEpoch ~/ 1000;
    await openFixture(tester, QuotaFixtureAdapter('Micro',
      [window('Weekly', 0, reset: reset)]));
    expect(find.text('WEEKLY'), findsOneWidget);
    expect(find.text('5-HOUR'), findsNothing);
    expect(find.byKey(const Key('micro-reset-weekly')), findsOneWidget);
    expect(find.byKey(const Key('micro-reset-quota')), findsNothing);
    expect(find.textContaining('RESET IN'), findsOneWidget);
    expect(find.text('0.0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching views retains a single weekly window without a new usage read',
      (tester) async {
    final adapter = QuotaFixtureAdapter('Full', [window('Weekly', 90)]);
    final controller = await openFixture(tester, adapter);
    final reads = adapter.usageReads;
    for (final mode in ['Monitor', 'Micro', 'Full']) {
      tester.view.physicalSize = viewSize(mode);
      controller.edit(compactMode: mode != 'Full', microMode: mode == 'Micro');
      await tester.pump(const Duration(milliseconds: 200));
      expectWindow(tester, mode, 0, 'Weekly', 90, 'weekly');
      expect(quotaRow(mode, 1), findsNothing);
      expect(find.text('5-HOUR'), findsNothing);
      expect(adapter.usageReads, reads);
      expect(tester.takeException(), isNull);
    }
  });
}
