import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/main.dart';
import 'package:codex_resume_flutter/bridge.dart';

class StubAdapter implements SchedulerAdapter {
  StubAdapter({this.includePending = false});
  final bool includePending;
  @override
  Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> payload = const {}]) async {
    if (action == 'load') {
      return {'sessions': [], 'pending': includePending ? [
        {'Name': 'CodexResume-20261103-1900-abcd1234',
          'When': '2026-11-03T19:00:00', 'Repo': r'C:\projects\long-repository-name',
          'Description': 'medium | read-only | long scheduled instruction',
          'Session': '11111111-1111-1111-1111-111111111111',
          'Status': 'Scheduled', 'CreatedAt': 1793732400}
      ] : [], 'history': [],
        'logDirectory': r'C:\scheduler\logs', 'settings': null};
    }
    if (action == 'usage') {
      return {'ok': true, 'models': [], 'model': null, 'windows': [],
        'accountId': null, 'ordinaryUsageAllowed': null};
    }
    return {'pending': [], 'history': []};
  }
}

void main() {
  testWidgets('v1.16 desktop geometry retains original row order and coordinates', (tester) async {
    tester.view.physicalSize = const Size(940, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: StubAdapter())));
    await tester.pump(const Duration(milliseconds: 150));
    final conversation = tester.getTopLeft(find.text('Conversation'));
    final repository = tester.getTopLeft(find.text('Repository root'));
    final runtime = tester.getTopLeft(find.text('Run at (local)'));
    final model = tester.getTopLeft(find.text('Model'));
    final instruction = tester.getTopLeft(find.text('Instruction'));
    final usage = tester.getTopLeft(find.text('Usage remaining'));
    expect(conversation.dx, closeTo(18, 4));
    expect(conversation.dy, closeTo(68, 8));
    expect(repository.dy, closeTo(115, 8));
    expect(runtime.dy, closeTo(161, 8));
    expect(model.dy, closeTo(206, 8));
    expect(instruction.dy, closeTo(250, 8));
    expect(usage.dy, closeTo(328, 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('original compact mode stacks windows instead of squeezing them together', (tester) async {
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: StubAdapter())));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('Compact mode: OFF'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Usage limits'), findsOneWidget);
    expect(find.text('Schedule once'), findsNothing);
    final title = tester.getTopLeft(find.text('Usage limits'));
    expect(title.dy, closeTo(70, 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact and full modes remain top-aligned', (tester) async {
    tester.view.physicalSize = const Size(1120, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter())));
    await tester.pump(const Duration(milliseconds: 150));
    final heading = find.text('Schedule a continuation');
    expect(tester.getTopLeft(heading).dy, lessThan(90));
    await tester.tap(find.text('Compact mode: OFF'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.getTopLeft(find.text('Codex Scheduler')).dy, lessThan(60));
    expect(tester.getTopLeft(find.text('Usage limits')).dy, lessThan(110));
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 800.0, 1024.0]) {
    testWidgets('Scheduler has no overflow at width '+width.toString(), (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(home: SchedulerHome(
        adapter: StubAdapter(includePending: true))));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      expect(find.text('Schedule a continuation'), findsOneWidget);
      expect(find.text('Schedule once'), findsOneWidget);
      expect(find.text('Usage remaining'), findsOneWidget);
      expect(find.text('Upcoming runs'), findsOneWidget);
      await tester.ensureVisible(find.text('Recent runs'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Recent runs'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Recent Codex runs'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  }
}
