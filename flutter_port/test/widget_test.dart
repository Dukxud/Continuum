import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/main.dart';
import 'package:codex_resume_flutter/bridge.dart';

class StubAdapter implements SchedulerAdapter {
  StubAdapter({this.includePending = false, this.pendingCount = 0,
    this.verifiedSession = false, this.exhaustedQuota = false,
    this.failUsage = false, this.failLoad = false,
    this.pendingStatus = 'Scheduled',
    this.pendingSchedule, this.pendingLabels});
  final bool includePending;
  final int pendingCount;
  final bool verifiedSession;
  final bool exhaustedQuota;
  final bool failUsage;
  final bool failLoad;
  final String pendingStatus;
  final Completer<Map<String, dynamic>>? pendingSchedule;
  final Completer<Map<String, dynamic>>? pendingLabels;
  final List<String> cancellations = [];
  @override
  Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> payload = const {}]) async {
    if (action == 'schedule' && pendingSchedule != null) {
      return pendingSchedule!.future;
    }
    if (action == 'labels') {
      return pendingLabels?.future ?? {'sessions': []};
    }
    if (action == 'cancel') {
      cancellations.add(payload['name'] as String);
      return {'status': 'Cancelled', 'warning': ''};
    }
    if (action == 'load') {
      if (failLoad) throw SchedulerException('Test startup bridge failure');
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
        'ordinaryUsageAllowed': !exhaustedQuota,
        if (exhaustedQuota) ...{
          'recommendationKind': 'exhausted-window',
          'recommendedResetAt': (() {
            final future = DateTime.now().add(const Duration(hours: 1));
            return DateTime(future.year, future.month, future.day,
              future.hour, future.minute, 37).millisecondsSinceEpoch ~/ 1000;
          })(),
        }};
    }
    return {'pending': [], 'history': []};
  }
}

/// Loads a saved CLI session without a repository. Only 'select' returns
/// the Git evidence, as it does in the production Windows bridge.
class AutoRepositoryAdapter extends StubAdapter {
  AutoRepositoryAdapter() : super(verifiedSession: true);

  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    if (action == 'select') {
      return {
        'sessionId': payload['sessionId'],
        'found': {'Root': r'C:\QA\auto-detected', 'AlternativeRoots': []},
        'model': 'gpt-test',
      };
    }
    final result = await super.call(action, payload);
    if (action == 'load') {
      final settings = Map<String, dynamic>.from(result['settings'] as Map);
      final draft = Map<String, dynamic>.from(settings['draft'] as Map);
      draft['repo'] = '';
      return {...result, 'settings': {...settings, 'draft': draft}};
    }
    return result;
  }
}

class LiveMonitoringAdapter extends StubAdapter {
  LiveMonitoringAdapter() : super(pendingCount: 1, pendingStatus: 'Running');

  static const job = 'CodexResume-20261103-1900-00000001';
  int polls = 0;

  Map<String, dynamic> activity(String summary, {int commands = 0}) => {
    'Available': true,
    'Summary': summary,
    'Recent': [summary],
    'CompletedCommands': commands,
    'FileChanges': 0,
    'LatestResponse': 'Checked repository and verified tests.',
  };

  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    if (action == 'load') {
      final data = await super.call(action, payload);
      return {...data, 'activities': {job: activity('Running command')}};
    }
    if (action == 'pending') {
      polls++;
      if (polls > 1) return {'pending': [], 'history': [], 'activities': {}};
      final data = await super.call('load');
      return {
        'pending': data['pending'], 'history': [],
        'activities': {job: activity('Command finished (exit 0)', commands: 1)},
      };
    }
    return super.call(action, payload);
  }
}

void main() {
  testWidgets('new workbench has distinct visual hierarchy', (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: StubAdapter())));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Continuum.'), findsOneWidget);
    expect(find.text('Choose your thread'), findsOneWidget);
    expect(find.text('Set the moment.'), findsOneWidget);
    expect(find.text('CAPACITY / LIVE'), findsOneWidget);
    expect(find.text('IN FLIGHT'), findsOneWidget);
    expect(find.text('Now +1'), findsOneWidget);
    expect(find.text('Schedule once'), findsOneWidget);
    final setup = tester.getTopLeft(find.text('Choose your thread'));
    final launch = tester.getTopLeft(find.text('Set the moment.'));
    final capacity = tester.getTopLeft(find.text('CAPACITY / LIVE'));
    expect(launch.dy, greaterThan(setup.dy + 150));
    expect(capacity.dx, greaterThan(setup.dx + 350));
    expect(tester.takeException(), isNull);
  });

  testWidgets('handoff glow has no rectangular clipping seam', (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: StubAdapter())));
    await tester.pump(const Duration(milliseconds: 150));

    final badge = find.text('SECOND-PRECISE');
    final handoffStack = find.ancestor(of: badge, matching: find.byType(Stack)).first;
    expect(tester.widget<Stack>(handoffStack).clipBehavior, Clip.none,
      reason: 'The inset Stack must not cut the ambient glow at its rectangular bounds.');

    final roundedCard = find.ancestor(of: handoffStack, matching: find.byType(ClipRRect)).first;
    expect(tester.widget<ClipRRect>(roundedCard).clipBehavior, isNot(Clip.none),
      reason: 'Glow remains constrained by the outer rounded card.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup failure is visible in the header', (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter(failLoad: true))));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('LOAD FAILED'), findsOneWidget);
    expect(find.text('CONNECTING'), findsNothing);
    expect(find.textContaining('Refresh failed:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slow activity labels cannot block startup or quota', (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final labels = Completer<Map<String, dynamic>>();
    final adapter = StubAdapter(verifiedSession: true, pendingLabels: labels);
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: adapter)));
    await tester.pump(const Duration(milliseconds: 150));

    // Cosmetic label request is deliberately unresolved. Essential data
    // must nevertheless be ready, selectable, and populated.
    expect(find.text('CONNECTED'), findsOneWidget);
    expect(find.text('QA project | verified CLI session'), findsOneWidget);
    expect(find.text('5-HOUR'), findsOneWidget);
    expect(find.text('Now +1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    labels.complete({'sessions': [{
      'Id': '11111111-1111-1111-1111-111111111111',
      'Display': 'Review shared-EC2 architecture | Outside Git: Nathan | 4 Nov 17:19 | 28dd756b',
    }]});
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Review shared-EC2 architecture'), findsOneWidget);
    expect(find.text('CONNECTED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-resume on quota is explicitly off until enabled',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter(verifiedSession: true))));
    await tester.pump(const Duration(milliseconds: 150));
    final toggle = find.byKey(const Key('auto-resume-on-limit'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.text('Auto-resume if usage limits stop Codex'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(find.text('Schedule once'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minus is left of date and time stays beside date',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: StubAdapter())));
    await tester.pump(const Duration(milliseconds: 150));
    final minus = find.text('−');
    final plus = find.text('+');
    final field = find.byKey(const Key('scheduled-date-picker'));
    final clock = find.byKey(const Key('selected-run-time-label'));
    expect(minus, findsOneWidget);
    expect(plus, findsOneWidget);
    expect(tester.getCenter(minus).dx, lessThan(tester.getTopLeft(field).dx));
    expect(tester.getCenter(plus).dx, greaterThan(tester.getTopRight(field).dx));
    final minusButton = find.ancestor(of: minus,
      matching: find.byType(InkWell)).first;
    final plusButton = find.ancestor(of: plus,
      matching: find.byType(InkWell)).first;
    final dateHeight = tester.getSize(field).height;
    expect(dateHeight, greaterThanOrEqualTo(38));
    expect(dateHeight, tester.getSize(minusButton).height);
    expect(dateHeight, tester.getSize(plusButton).height);
    final date = find.descendant(of: field, matching: find.byType(Text)).first;
    expect((tester.getCenter(date).dy - tester.getCenter(clock).dy).abs(), lessThan(8));
    final value = tester.widget<Text>(clock).data!;
    expect(value, matches(RegExp(r'^\d{1,2}:\d{2}:\d{2} (AM|PM)$')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('adaptive +1 shortcut preserves recommended seconds',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter(verifiedSession: true))));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Now +1'), findsOneWidget);
    expect(find.text('Reset +1'), findsNothing);
    await tester.tap(find.text('Now +1'));
    await tester.pump();
    final nowLabel = tester.widget<Text>(
      find.byKey(const Key('selected-run-time-label'))).data!;
    expect(nowLabel, matches(RegExp(r'\d{1,2}:\d{2}:\d{2} (AM|PM)$')));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      key: const ValueKey('reset-mode'),
      adapter: StubAdapter(verifiedSession: true, exhaustedQuota: true))));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Now +1'), findsNothing);
    expect(find.text('Reset +1'), findsOneWidget);
    await tester.tap(find.text('Reset +1'));
    await tester.pump();
    final resetLabel = tester.widget<Text>(
      find.byKey(const Key('selected-run-time-label'))).data!;
    expect(resetLabel, contains(':37 '));
    expect(tester.takeException(), isNull);
  });

  testWidgets('date picker uses Monday as the first day of the week',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US'), Locale('en', 'GB')],
      home: SchedulerHome(adapter: StubAdapter()),
    ));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.byKey(const Key('selected-run-time-label')));
    await tester.pump(const Duration(milliseconds: 350));
    final calendar = find.byType(DatePickerDialog);
    expect(calendar, findsOneWidget);
    expect(MaterialLocalizations.of(tester.element(calendar)).firstDayOfWeekIndex,
      1, reason: 'Calendar grid must start on Monday, not Sunday');
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup discovery visibly fills the repository field without a dropdown click',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: AutoRepositoryAdapter())));
    await tester.pump(const Duration(milliseconds: 150));
    final repositoryField = tester.widget<TextField>(
      find.byKey(const Key('repository-root-field')));
    expect(repositoryField.controller?.text, r'C:\QA\auto-detected');
    expect(find.text('Repository unresolved; use Browse.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monitor is distinct and restores the full workbench',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: StubAdapter())));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('Monitor'));
    await tester.pump(const Duration(milliseconds: 150));
    tester.view.physicalSize = const Size(540, 685);
    await tester.pump();
    expect(find.text('On watch.'), findsOneWidget);
    expect(find.text('Full view'), findsOneWidget);
    expect(find.text('Set the moment.'), findsNothing);
    final first = tester.getTopLeft(find.text('5-HOUR'));
    final second = tester.getTopLeft(find.text('WEEKLY'));
    expect(second.dy, greaterThan(first.dy + 120));
    await tester.tap(find.text('Full view'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Continuum.'), findsOneWidget);
    expect(find.text('Schedule once'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('running Codex event feed updates and clears in both monitor modes',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final adapter = LiveMonitoringAdapter();
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: adapter)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('live-codex-activity')), findsOneWidget);
    expect(find.text('Running command'), findsOneWidget);
    await tester.tap(find.text('Monitor'));
    await tester.pump(const Duration(milliseconds: 150));
    tester.view.physicalSize = const Size(540, 685);
    await tester.pump();
    expect(find.byKey(const Key('live-codex-activity')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Command finished (exit 0)'), findsOneWidget);
    expect(find.textContaining('1 commands'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('live-codex-activity')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all queued jobs remain reachable in bounded list', (tester) async {
    tester.view.physicalSize = const Size(1240, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter(pendingCount: 7))));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('7 ACTIVE'), findsOneWidget);
    final list = find.byKey(const PageStorageKey<String>('upcoming-run-list'));
    expect(list, findsOneWidget);
    await tester.drag(list, const Offset(0, -900));
    await tester.pump();
    expect(find.text('Scheduled item 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exhausted quota still permits a verified future schedule',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
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
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter(failUsage: true))));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Usage unavailable · automatic retry'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('close does not terminate an in-flight scheduling operation',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final request = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: StubAdapter(verifiedSession: true, pendingSchedule: request))));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('Schedule once'));
    await tester.pump();
    final state = tester.state(find.byType(SchedulerHome));
    // Exercise the actual public WindowListener callback without installing
    // a native window_manager plugin in a headless widget test.
    (state as dynamic).onWindowClose();
    await tester.pump();
    expect(find.text('Scheduling or cancellation is still in progress.'), findsOneWidget);
    request.complete({'name': 'CodexResume-20261104-1500-12345678'});
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('running jobs show Running and cannot be cancelled',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 850);
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
    await tester.tap(find.text('Monitor'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('RUNNING'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel selected goes directly to Windows adapter without confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final adapter = StubAdapter(pendingCount: 1);
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: adapter)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('1 ACTIVE'), findsOneWidget);
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

  for (final width in [320.0, 800.0, 1024.0, 1240.0]) {
    testWidgets('workbench remains accessible at width ' + width.toString(),
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
      await tester.pumpWidget(MaterialApp(home: SchedulerHome(
        adapter: StubAdapter(includePending: true))));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      expect(find.text('Continuum.'), findsOneWidget);
      expect(find.text('Schedule once'), findsOneWidget);
      expect(find.text('CAPACITY / LIVE'), findsOneWidget);
      expect(find.text('1 ACTIVE'), findsOneWidget);
      await tester.ensureVisible(find.text('History'));
      await tester.pump();
      await tester.tap(find.text('History'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Recent Codex runs'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  }
}
