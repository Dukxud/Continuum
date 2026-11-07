import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/desktop_window.dart';
import 'package:codex_resume_flutter/main.dart';

class SpyWindowHost implements SchedulerWindowHost {
  final List<String> modes = [];
  final List<bool> topmostCalls = [];
  bool rejectPin = false;
  @override
  Future<void> setAlwaysOnTop(bool enabled) async {
    topmostCalls.add(enabled);
    if (rejectPin) throw SchedulerException('Native pin failed');
  }
  @override
  Future<void> setMode({required bool compact, bool micro = false,
      required int upcomingRunCount,
      required int quotaWindowCount}) async {
    modes.add((micro ? 'micro' : compact ? 'compact' : 'standard') +
      (upcomingRunCount > 0 ? ':run' : ':empty') +
      ':quota:$quotaWindowCount');
  }
  @override
  Future<void> showDialogWindow({required bool history}) async {}

  final List<String> shutdownCalls = [];
  @override
  Future<void> hideForShutdown() async { shutdownCalls.add('hide'); }
  @override
  Future<void> restoreAfterFailedShutdown() async { shutdownCalls.add('restore'); }
  @override
  Future<void> finishShutdown() async { shutdownCalls.add('finish'); }
}

class WindowAdapter implements SchedulerAdapter {
  WindowAdapter({required this.startCompact, this.hasRun = false,
    this.quotaWindowCount = 0, this.startMicro = false,
    this.startPinned = false, this.emptyFiveHour = false,
    this.knownReset = false});
  final bool startCompact;
  final bool hasRun;
  final int quotaWindowCount;
  final bool startMicro;
  final bool startPinned;
  final bool emptyFiveHour;
  final bool knownReset;
  int usageRequests = 0;
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
        'settings': {'compactMode': startCompact, 'microMode': startMicro,
          'alwaysOnTop': startPinned, 'draft': {}},
      };
    }
    if (action == 'usage') {
      usageRequests++;
      return {'ok': true, 'model': payload['model'] ?? 'gpt-test',
        'models': [{'id': 'gpt-test', 'efforts': ['medium']},
          {'id': 'gpt-run', 'efforts': ['medium']}],
        'windows': List.generate(quotaWindowCount, (i) => {
          'label': i == 0 ? '5-hour' : 'Weekly',
          'remainingPercent': emptyFiveHour && i == 0 ? 0.0 : 70.0,
          if (knownReset) 'resetsAt': DateTime.now()
            .add(const Duration(hours: 2))
            .millisecondsSinceEpoch ~/ 1000,
        }), 'ordinaryUsageAllowed': true,
        'accountId': 'workspace-sha256:' + 'a' * 64};
    }
    if (action == 'pending') {
      return {'pending': [], 'history': []};
    }
    return {};
  }
}

class ShutdownWindowAdapter extends WindowAdapter {
  ShutdownWindowAdapter() : super(startCompact: false);
  final Completer<void> saveGate = Completer<void>();
  final List<Map<String, dynamic>> snapshots = [];
  bool waitForSave = false;
  bool rejectSave = false;

  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    if (action != 'save') return super.call(action, payload);
    snapshots.add(Map<String, dynamic>.from(payload));
    if (waitForSave) await saveGate.future;
    if (rejectSave) throw SchedulerException('Disk write denied');
    return {'saved': true};
  }
}

Future<void> chooseView(WidgetTester tester, String label, {Size? nextSize}) async {
  await tester.tap(find.byKey(const Key('view-menu')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.text(label).last);
  if (nextSize != null) tester.view.physicalSize = nextSize;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('unchanged close hides and exits without spawning a save',
      (tester) async {
    final host = SpyWindowHost();
    final adapter = ShutdownWindowAdapter();
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: adapter, windowHost: host)));
    await tester.pump(const Duration(milliseconds: 160));
    final home = tester.state(find.byType(SchedulerHome));
    (home as dynamic).onWindowClose();
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.shutdownCalls, ['hide', 'finish']);
    expect(adapter.snapshots, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dirty close hides before a slow save and exits only afterward',
      (tester) async {
    final host = SpyWindowHost();
    final adapter = ShutdownWindowAdapter()..waitForSave = true;
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: adapter, windowHost: host)));
    await tester.pump(const Duration(milliseconds: 160));
    final home = tester.state(find.byType(SchedulerHome));
    (home as dynamic).controller.edit(instruction: 'Latest edit');
    (home as dynamic).onWindowClose();
    await tester.pump(const Duration(milliseconds: 100));
    expect(host.shutdownCalls, ['hide']);
    expect(adapter.snapshots, hasLength(1));
    expect((adapter.snapshots.single['draft'] as Map)['message'], 'Latest edit');
    adapter.saveGate.complete();
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.shutdownCalls, ['hide', 'finish']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save failure restores hidden window; a later close may succeed',
      (tester) async {
    final host = SpyWindowHost();
    final adapter = ShutdownWindowAdapter()..rejectSave = true;
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: adapter, windowHost: host)));
    await tester.pump(const Duration(milliseconds: 160));
    final home = tester.state(find.byType(SchedulerHome));
    (home as dynamic).controller.edit(instruction: 'Keep this draft');
    (home as dynamic).onWindowClose();
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.shutdownCalls, ['hide', 'restore']);
    expect(find.textContaining('Unable to close safely:'), findsOneWidget);
    adapter.rejectSave = false;
    (home as dynamic).onWindowClose();
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.shutdownCalls, ['hide', 'restore', 'hide', 'finish']);
    expect(adapter.snapshots, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Micro restores topmost and reports absent quota without scheduling',
      (tester) async {
    tester.view.physicalSize = const Size(392, 212);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final host = SpyWindowHost();
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: true,
        startMicro: true, startPinned: true),
      windowHost: host)));
    await tester.pump(const Duration(milliseconds: 180));
    expect(host.modes, contains('micro:empty:quota:0'));
    expect(host.topmostCalls, [true]);
    expect(find.text('Micro monitor'), findsOneWidget);
    expect(find.text('5-HOUR'), findsNothing);
    expect(find.text('WEEKLY'), findsNothing);
    expect(find.text('No usage windows reported'), findsOneWidget);
    expect(find.text('NO RUNS IN FLIGHT'), findsOneWidget);
    expect(find.text('Schedule once'), findsNothing);
    expect(find.text('Cancel selected'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('pin-window')));
    await tester.pump();
    expect(host.topmostCalls, [true, false]);
    await chooseView(tester, 'Monitor', nextSize: const Size(540, 535));
    expect(host.modes, contains('compact:empty:quota:0'));
    expect(find.text('On watch.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native pin toggles independently of Micro and returns to Full',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final host = SpyWindowHost();
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: false),
      windowHost: host)));
    await tester.pump(const Duration(milliseconds: 180));
    expect(host.topmostCalls, isEmpty);
    await tester.tap(find.byKey(const Key('pin-window')));
    await tester.pump();
    expect(host.topmostCalls, [true]);
    expect(find.byKey(const Key('pin-window')), findsOneWidget);
    await chooseView(tester, 'Micro', nextSize: const Size(392, 212));
    expect(host.modes, contains('micro:empty:quota:0'));
    expect(find.byKey(const Key('pin-window')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await chooseView(tester, 'Full', nextSize: const Size(1240, 850));
    expect(find.text('Continuum.'), findsOneWidget);
    expect(find.byKey(const Key('pin-window')), findsOneWidget);
    expect(host.modes, contains('standard:empty:quota:0'));
    await tester.tap(find.byKey(const Key('pin-window')));
    await tester.pump();
    expect(host.topmostCalls, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed native restore clears displayed pin', (tester) async {
    tester.view.physicalSize = const Size(392, 212);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final host = SpyWindowHost()..rejectPin = true;
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: true, startMicro: true,
        startPinned: true), windowHost: host)));
    await tester.pump(const Duration(milliseconds: 180));
    expect(host.topmostCalls, [true]);
    final home = tester.state(find.byType(SchedulerHome));
    expect((home as dynamic).controller.alwaysOnTop, isFalse);
    expect(find.byTooltip('Always on Top'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed manual pin never claims topmost', (tester) async {
    tester.view.physicalSize = const Size(392, 212);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final host = SpyWindowHost()..rejectPin = true;
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: true, startMicro: true),
      windowHost: host)));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(find.byKey(const Key('pin-window')));
    await tester.pump();
    final home = tester.state(find.byType(SchedulerHome));
    expect((home as dynamic).controller.alwaysOnTop, isFalse);
    expect(host.topmostCalls, [true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('View stays at the same right-edge offset across modes',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: false))));
    await tester.pump(const Duration(milliseconds: 180));
    double rightOffset() => tester.view.physicalSize.width -
      tester.getRect(find.byKey(const Key('view-menu'))).right;
    final fullOffset = rightOffset();
    await chooseView(tester, 'Monitor', nextSize: const Size(540, 535));
    expect(rightOffset(), closeTo(fullOffset, 1));
    await chooseView(tester, 'Micro', nextSize: const Size(392, 212));
    expect(rightOffset(), closeTo(fullOffset, 1));
    expect(tester.takeException(), isNull);
  });

  test('upper-right pivot survives mode and dialog roundtrips', () {
    const starting = Rect.fromLTWH(920, 50, 392, 212);
    final monitor = anchoredTopRightBounds(starting, const Size(540, 535));
    expect(monitor.right, starting.right);
    expect(monitor.top, starting.top);
    final full = anchoredTopRightBounds(monitor, const Size(1240, 850));
    expect(full.right, starting.right);
    expect(full.top, starting.top);
    final dialog = anchoredTopRightBounds(starting, const Size(1040, 780));
    expect(dialog.right, starting.right);
    expect(anchoredTopRightBounds(dialog, starting.size), starting);
    expect(anchoredTopRightBounds(full, starting.size), starting);
    // Secondary-monitor coordinates can be negative.
    const secondary = Rect.fromLTWH(-1500, 75, 540, 535);
    expect(anchoredTopRightBounds(secondary, const Size(392, 212)).right,
      secondary.right);
  });

  testWidgets('Micro shows actual reset and countdown when exhausted',
      (tester) async {
    tester.view.physicalSize = const Size(392, 212);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: true, startMicro: true,
        quotaWindowCount: 2, emptyFiveHour: true, knownReset: true))));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('micro-reset-quota')), findsOneWidget);
    expect(find.byKey(const Key('micro-bar-quota')), findsNothing);
    expect(find.textContaining('RESET IN'), findsOneWidget);
    expect(find.byKey(const Key('micro-bar-weekly')), findsOneWidget);
    expect(find.byKey(const Key('micro-reset-time-quota')), findsOneWidget);
    expect(find.byKey(const Key('micro-reset-time-weekly')), findsOneWidget);
    expect(find.textContaining('RESETS'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Micro does not invent a reset timestamp', (tester) async {
    tester.view.physicalSize = const Size(392, 212);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: true, startMicro: true,
        quotaWindowCount: 2, emptyFiveHour: true))));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('RESET UNKNOWN'), findsOneWidget);
    expect(find.text('RESET TIME UNAVAILABLE'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  test('full and compact modes always fit content, regardless of prior size', () {
    expect(schedulerWindowSize(compact: false,
      upcomingRunCount: 0, quotaWindowCount: 2), const Size(1240, 850));
    expect(schedulerWindowSize(compact: true, micro: true,
      upcomingRunCount: 1, quotaWindowCount: 2), const Size(392, 212));
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

  testWidgets('view switching preserves same-model quota without new reads',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final host = SpyWindowHost();
    final adapter = WindowAdapter(startCompact: false, quotaWindowCount: 2);
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: adapter, windowHost: host)));
    await tester.pump(const Duration(milliseconds: 180));
    final reads = adapter.usageRequests;
    expect(reads, greaterThan(0));
    await chooseView(tester, 'Monitor', nextSize: const Size(540, 535));
    await chooseView(tester, 'Micro', nextSize: const Size(392, 212));
    await chooseView(tester, 'Full', nextSize: const Size(1240, 850));
    expect(adapter.usageRequests, reads);
    expect(tester.takeException(), isNull);
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
    await chooseView(tester, 'Monitor', nextSize: const Size(540, 535));
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
