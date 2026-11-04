import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/main.dart';
import 'package:codex_resume_flutter/windows_icons.dart';
import 'package:codex_resume_flutter/bridge.dart';

class StubAdapter implements SchedulerAdapter {
  StubAdapter({this.includePending = false, this.pendingCount = 0,
    this.verifiedSession = false, this.exhaustedQuota = false,
    this.failUsage = false, this.pendingStatus = 'Scheduled'});
  final bool includePending;
  final int pendingCount;
  final bool verifiedSession;
  final bool exhaustedQuota;
  final bool failUsage;
  final String pendingStatus;
  final List<String> cancellations = [];
  @override
  Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> payload = const {}]) async {
    if (action == 'cancel') {
      cancellations.add(payload['name'] as String);
      return {'status': 'Cancelled', 'warning': ''};
    }
    if (action == 'load') {
      return {'sessions': verifiedSession ? [
        {'Id': '11111111-1111-1111-1111-111111111111',
         'Display': 'QA project | verified CLI session'}
      ] : [], 'pending': pendingCount > 0
        ? List.generate(pendingCount, (i) => {
          'Name': 'CodexResume-20261103-1900-${(i + 1).toRadixString(16).padLeft(8, '0')}',
          'When': '2026-11-03T19:00:00', 'Repo': r'C:\projects\fixture',
          'Description': 'Scheduled item ${i + 1}',
          'Session': '11111111-1111-1111-1111-111111111111',
          'Status': pendingStatus, 'CreatedAt': 1793732400,
        }) : includePending ? [
        {'Name': 'CodexResume-20261103-1900-abcd1234',
          'When': '2026-11-03T19:00:00', 'Repo': r'C:\projects\long-repository-name',
          'Description': 'medium | read-only | long scheduled instruction',
          'Session': '11111111-1111-1111-1111-111111111111',
          'Status': pendingStatus, 'CreatedAt': 1793732400}
      ] : [], 'history': [],
        'logDirectory': r'C:\scheduler\logs', 'settings': verifiedSession
          ? {'draft': {
              'sessionId': '11111111-1111-1111-1111-111111111111',
              'model': 'gpt-test', 'effort': 'medium',
              'repo': r'C:\projects\fixture', 'access': 'read-only',
            }}
          : null};
    }
    if (action == 'usage') {
      if (failUsage) throw SchedulerException('Transient live quota failure');
      return {'ok': true,
        'models': [{'id': 'gpt-test', 'name': 'Test model',
          'efforts': ['medium'], 'defaultEffort': 'medium', 'isDefault': true}],
        'model': 'gpt-test',
        'windows': [
          {'label': '5-hour', 'remainingPercent': 71.0, 'resetsAt': 1793736000},
          {'label': 'Weekly', 'remainingPercent': 45.0, 'resetsAt': 1794200000}
        ],
        'accountId': 'workspace-sha256:' + 'a' * 64,
        'ordinaryUsageAllowed': !exhaustedQuota};
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
    expect(find.text('Browse'), findsOneWidget);
    expect(find.byType(WindowsCalendarGlyph), findsOneWidget);
    expect(find.byType(WindowsCaret), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('original compact mode stacks windows instead of squeezing them together', (tester) async {
    // Real full mode has a 940px minimum width. Switch modes while the
    // toggle is reachable, then simulate the native compact resize.
    tester.view.physicalSize = const Size(940, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: StubAdapter())));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('Compact mode: OFF'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Compact mode: ON'), findsOneWidget);
    tester.view.physicalSize = const Size(480, 800);
    await tester.pump();
    expect(find.text('Usage limits'), findsOneWidget);
    expect(find.text('Schedule once'), findsNothing);
    final title = tester.getTopLeft(find.text('Usage limits'));
    expect(title.dy, closeTo(70, 8));
    final primary = tester.getTopLeft(find.text('5-hour'));
    final secondary = tester.getTopLeft(find.text('Weekly'));
    expect(primary.dy, lessThan(secondary.dy));
    expect(secondary.dy - primary.dy, closeTo(117, 7));
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

  testWidgets('all scheduled tasks remain reachable by scrolling four-row grid', (tester) async {
    tester.view.physicalSize = const Size(940, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter(pendingCount: 7))));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Upcoming runs (7)'), findsOneWidget);
    final list = find.byKey(const PageStorageKey<String>('upcoming-run-list'));
    expect(list, findsOneWidget);
    await tester.drag(list, const Offset(0, -300));
    await tester.pump();
    expect(find.text('Scheduled item 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exhausted quota still permits a verified future schedule',
      (tester) async {
    tester.view.physicalSize = const Size(940, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter(verifiedSession: true, exhaustedQuota: true))));
    await tester.pump(const Duration(milliseconds: 150));
    final schedule = find.ancestor(
      of: find.text('Schedule once'), matching: find.byType(InkWell)).first;
    expect(tester.widget<InkWell>(schedule).onTap, isNotNull,
      reason: 'the worker rechecks quota at execution; scheduling later is allowed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('usage failures show actionable feedback inside both cards',
      (tester) async {
    tester.view.physicalSize = const Size(940, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter(failUsage: true))));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Usage unavailable; retrying automatically'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('running jobs show Running and cannot be cancelled',
      (tester) async {
    tester.view.physicalSize = const Size(940, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter(pendingCount: 1, pendingStatus: 'Running'))));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('Scheduled item 1'));
    await tester.pump();
    final cancelButton = find.ancestor(
      of: find.text('Cancel selected'), matching: find.byType(InkWell)).first;
    expect(tester.widget<InkWell>(cancelButton).onTap, isNull);
    await tester.tap(find.text('Compact mode: OFF'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Running'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel selected goes directly to Windows adapter without confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(940, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final adapter = StubAdapter(pendingCount: 1);
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: adapter)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Upcoming runs (1)'), findsOneWidget);
    await tester.tap(find.text('Scheduled item 1'));
    await tester.pump();
    expect(find.text('Cancel selected'), findsOneWidget);
    await tester.tap(find.text('Cancel selected'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(adapter.cancellations, [
      'CodexResume-20261103-1900-00000001',
    ]);
    expect(find.byType(AlertDialog), findsNothing);
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
      expect(find.text('Upcoming runs (1)'), findsOneWidget);
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
