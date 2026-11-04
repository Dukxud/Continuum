import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/desktop_window.dart';
import 'package:codex_resume_flutter/main.dart';

class SpyWindowHost implements SchedulerWindowHost {
  final List<String> modes = [];
  @override
  Future<void> setMode({required bool compact, required int upcomingRunCount,
      required int quotaWindowCount}) async {
    modes.add((compact ? 'compact' : 'standard') +
      (upcomingRunCount > 0 ? ':run' : ':empty') +
      ':quota:$quotaWindowCount');
  }
  @override
  Future<void> showDialogWindow({required bool history}) async {}

}

class WindowAdapter implements SchedulerAdapter {
  WindowAdapter({required this.startCompact, this.hasRun = false,
    this.quotaWindowCount = 0});
  final bool startCompact;
  final bool hasRun;
  final int quotaWindowCount;
  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    if (action == 'load') {
      return {
        'sessions': [], 'history': [],
        'pending': hasRun ? [
          {'Name': 'CodexResume-20261103-1900-abcd1234',
           'When': '2026-11-03T19:00:00',
           'Status': 'Scheduled', 'Model': 'gpt-run',
           'Repo': r'C:\projects\test', 'Session': '-'}
        ] : [],
        'settings': {'compactMode': startCompact, 'draft': {}},
      };
    }
    if (action == 'usage') {
      return {'ok': true, 'model': payload['model'] ?? 'gpt-test',
        'models': [{'id': 'gpt-test', 'efforts': ['medium']},
          {'id': 'gpt-run', 'efforts': ['medium']}],
        'windows': List.generate(quotaWindowCount, (i) => {
          'label': i == 0 ? '5-hour' : 'Weekly',
          'remainingPercent': 70.0,
        }), 'ordinaryUsageAllowed': true,
        'accountId': 'workspace-sha256:' + 'a' * 64};
    }
    if (action == 'pending') {
      return {'pending': [], 'history': []};
    }
    return {};
  }
}

void main() {
  test('full and compact modes always fit content, regardless of prior size', () {
    expect(schedulerWindowSize(compact: false,
      upcomingRunCount: 0, quotaWindowCount: 2), const Size(1240, 850));
    expect(schedulerWindowSize(compact: false,
      upcomingRunCount: 1, quotaWindowCount: 2), const Size(1240, 850));
    expect(schedulerWindowSize(compact: true,
      upcomingRunCount: 0, quotaWindowCount: 2), const Size(540, 535));
    expect(schedulerWindowSize(compact: true,
      upcomingRunCount: 0, quotaWindowCount: 0), const Size(540, 535));
    expect(schedulerWindowSize(compact: true,
      upcomingRunCount: 1, quotaWindowCount: 2), const Size(540, 685));
  });

  test('resizes are serialized and one failure does not block later modes', () async {
    final queue = WindowActionQueue();
    final gate = Completer<void>();
    final calls = <String>[];
    final first = queue.enqueue(() async {
      calls.add('first-start');
      await gate.future;
      calls.add('first-end');
    });
    final second = queue.enqueue(() async { calls.add('second'); throw StateError('boom'); });
    final last = queue.enqueue(() async { calls.add('final-mode'); });
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['first-start']);
    gate.complete();
    final rejected = expectLater(second, throwsStateError);
    await first;
    await rejected;
    await last;
    expect(calls, ['first-start', 'first-end', 'second', 'final-mode']);
  });

  testWidgets('compact mode changes the host window size, not only controls', (tester) async {
    // The native workbench is wide; render it at the actual desktop size.
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    final host = SpyWindowHost();
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: false),
      windowHost: host)));
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.modes, contains('standard:empty:quota:0'));
    await tester.tap(find.text('Monitor'));
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.modes, contains('compact:empty:quota:0'));
    expect(find.text('Schedule once'), findsNothing);
    expect(find.text('On watch.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact host follows quota availability without synthetic cards', (tester) async {
    final host = SpyWindowHost();
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: true, quotaWindowCount: 2),
      windowHost: host)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(host.modes, contains('compact:empty:quota:2'));
    expect(find.text('CAPACITY'), findsOneWidget);
    expect(find.text('5-HOUR'), findsOneWidget);
    expect(find.text('WEEKLY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved compact preference opens a compact window', (tester) async {
    final host = SpyWindowHost();
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: true),
      windowHost: host)));
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.modes.first, 'compact:empty:quota:0');
    expect(tester.takeException(), isNull);
  });
}
