import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/aero_appearance.dart';
import 'package:codex_resume_flutter/scheduler_controller.dart';

class FakeScheduler implements SchedulerAdapter {
  final List<String> actions = [];
  final List<Map<String, dynamic>> saves = [];
  @override
  Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> payload = const {}]) async {
    actions.add(action);
    switch (action) {
      case 'load':
        return {
          'sessions': [{'Id': '11111111-1111-1111-1111-111111111111',
            'Display': 'Test project | saved CLI session'}],
          'pending': [], 'history': [], 'logDirectory': r'C:\scheduler\logs',
          'settings': {'draft': {
            'sessionId': '11111111-1111-1111-1111-111111111111',
            'model': 'gpt-test', 'effort': 'medium',
            'access': 'read-only', 'message': 'Resume.',
            'repo': r'C:\source\test'
          }}
        };
      case 'usage':
        return {
          'model': 'gpt-test', 'ok': true,
          'accountId': 'workspace-sha256:' + 'a' * 64,
          'ordinaryUsageAllowed': true,
          'models': [{'id': 'gpt-test', 'name': 'Test model',
            'efforts': ['low', 'medium'], 'defaultEffort': 'medium'}],
          'windows': []
        };
      case 'pending':
        return {'pending': [], 'history': []};
      case 'schedule':
        return {'name': 'CodexResume-20261103-1400-12345678', 'status': 'Scheduled'};
      case 'save':
        saves.add(payload);
        return {'saved': true};
      default:
        return {};
    }
  }
}

/// An exhausted quota can still be scheduled for after its reset.
/// The Windows worker remains responsible for execution-time admission.
class ExhaustedQuotaScheduler extends FakeScheduler {
  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    final result = await super.call(action, payload);
    if (action != 'usage') return result;
    return {
      ...result,
      'ordinaryUsageAllowed': false,
      'windows': [{
        'label': '5-hour',
        'remainingPercent': 0.0,
        'resetsAt': 1793736000,
      }],
      'recommendationKind': 'exhausted-window',
      'recommendedResetAt': 1793736000,
    };
  }
}

class FailOnceLoadScheduler extends FakeScheduler {
  bool firstLoad = true;
  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) {
    if (action == 'load' && firstLoad) {
      firstLoad = false;
      return Future.error(SchedulerException('Temporary launch failure'));
    }
    return super.call(action, payload);
  }
}

class RejectSaveScheduler extends FakeScheduler {
  bool reject = true;
  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) {
    if (action == 'save' && reject) {
      return Future.error(SchedulerException('Permission denied'));
    }
    return super.call(action, payload);
  }
}

class DeferredSaveScheduler extends FakeScheduler {
  final firstSaveEntered = Completer<void>();
  final releaseFirstSave = Completer<void>();
  int inProgress = 0;
  int maxSimultaneous = 0;

  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    if (action != 'save') return super.call(action, payload);
    inProgress++;
    if (inProgress > maxSimultaneous) maxSimultaneous = inProgress;
    final snapshot = Map<String, dynamic>.from(payload);
    if (saves.isEmpty) {
      firstSaveEntered.complete();
      await releaseFirstSave.future;
    }
    saves.add(snapshot);
    inProgress--;
    return {'saved': true};
  }
}

class RepositoryLookupScheduler extends FakeScheduler {
  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    if (action == 'select') {
      return {
        'model': 'gpt-test',
        'found': {'Root': r'C:\verified\checkout', 'AlternativeRoots': []},
      };
    }
    return super.call(action, payload);
  }
}

/// Mimics the real adapter: loading recent CLI sessions does not implicitly
/// resolve their repositories; only the separate 'select' action does.
class StartupRepositoryScheduler extends FakeScheduler {
  StartupRepositoryScheduler({
    this.savedSessionId = '11111111-1111-1111-1111-111111111111',
    this.savedRepository = '',
    this.roots = const [r'C:\discovered\checkout'],
  });

  String savedSessionId;
  String savedRepository;
  List<String?> roots;
  List<Map<String, dynamic>> availableSessions = [
    {'Id': '11111111-1111-1111-1111-111111111111', 'Display': 'CLI checkout'},
  ];
  int lookups = 0;
  Completer<Map<String, dynamic>>? deferredSelection;

  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    final original = await super.call(action, payload);
    if (action == 'load') {
      final settings = Map<String, dynamic>.from(original['settings'] as Map);
      final draft = Map<String, dynamic>.from(settings['draft'] as Map);
      draft['sessionId'] = savedSessionId;
      draft['repo'] = savedRepository;
      return {
        ...original,
        'sessions': availableSessions,
        'settings': {...settings, 'draft': draft},
      };
    }
    if (action == 'select') {
      lookups++;
      if (deferredSelection != null) return deferredSelection!.future;
      final index = (lookups - 1).clamp(0, roots.length - 1);
      final root = roots[index];
      return {
        'sessionId': payload['sessionId'],
        'model': 'gpt-test',
        'found': root == null ? null :
          {'Root': root, 'AlternativeRoots': <String>[]},
      };
    }
    return original;
  }
}

class PendingRepositoryLookupScheduler extends FakeScheduler {
  final lookup = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) {
    if (action == 'select') return lookup.future;
    return super.call(action, payload);
  }
}

class ConflictingRepositoryScheduler extends FakeScheduler {
  @override
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> payload = const {}]) async {
    if (action == 'select') {
      return {
        'model': 'gpt-test',
        'found': {
          'Root': '',
          'Source': 'conflicting fallback worktrees',
          'Candidates': [r'C:\worktree\one', r'C:\worktree\two'],
        },
      };
    }
    return super.call(action, payload);
  }
}

void main() {
  test('adapter timeout never asserts failed registration or cancellation', () {
    for (final action in ['schedule', 'cancel', 'save', 'hide']) {
      final outcome = adapterTimeoutError(action);
      expect(outcome, isA<SchedulerOutcomeUncertain>());
      expect(outcome.toString(), contains('Outcome uncertain'));
    }
    expect(adapterTimeoutError('usage'), isNot(isA<SchedulerOutcomeUncertain>()));
    expect(adapterTimeoutError('browse'), isNot(isA<SchedulerOutcomeUncertain>()));
  });

  test('date helpers round forward and never schedule too close to now', () {
    final now = DateTime(2026, 11, 3, 14, 3, 48);
    expect(suggestedRunAt(now), DateTime(2026, 11, 3, 14, 6));
    expect(earliestRunAt(now), DateTime(2026, 11, 3, 14, 5));
    expect(stepRunAt(DateTime(2026, 11, 3, 14, 2), 1, now),
      DateTime(2026, 11, 3, 14, 5));
    expect(stepRunAt(DateTime(2026, 11, 3, 14, 2), -1, now),
      DateTime(2026, 11, 3, 14, 2));
    expect(localIsoMinute(now), '2026-11-03T14:03:00');
  });

  test('controller uses live identity and model-specific catalog before scheduling', () async {
    final fake = FakeScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    expect(controller.canSchedule, isTrue);
    expect(controller.sessionId, '11111111-1111-1111-1111-111111111111');
    final name = await controller.schedule(confirmUnrestricted: false, confirmOverlap: false);
    expect(name, startsWith('CodexResume-'));
    expect(fake.actions, contains('usage'));
    expect(fake.actions, contains('schedule'));
    controller.dispose();
  });

  test('schedule and cancel trigger one complete system refresh without blocking the result', () async {
    final fake = FakeScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    final initial = fake.actions.where((x) => x == 'load').length;
    await controller.schedule(confirmUnrestricted:false,confirmOverlap:false);
    await Future<void>.delayed(const Duration(milliseconds:10));
    expect(fake.actions.where((x) => x == 'load').length, initial + 1);
    await controller.cancel('CodexResume-20261103-1400-12345678');
    await Future<void>.delayed(const Duration(milliseconds:10));
    expect(fake.actions.where((x) => x == 'load').length, initial + 2);
    expect(fake.actions.where((x) => x == 'usage').length, 3);
    controller.dispose();
  });

  test('exhausted live quota does not disable future scheduling', () async {
    final fake = ExhaustedQuotaScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    expect(controller.canSchedule, isTrue,
      reason: 'WinForms allows registering a future run after quota reset');
    final name = await controller.schedule(
      confirmUnrestricted: false, confirmOverlap: false);
    expect(name, startsWith('CodexResume-'));
    expect(fake.actions, contains('schedule'));
    controller.dispose();
  });

  test('startup recovers and restores the draft after a transient load error', () async {
    final fake = FailOnceLoadScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    expect(controller.ready, isFalse);
    await controller.refreshOnFocus(DateTime.now().add(const Duration(seconds: 16)));
    expect(controller.ready, isTrue);
    expect(controller.sessionId, '11111111-1111-1111-1111-111111111111');
    expect(controller.repo, r'C:\source\test');
    controller.dispose();
  });

  test('focus refreshes stale data, not every quick return', () async {
    final fake = FakeScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    final initialReads = fake.actions.where((x) => x == 'load').length;
    await controller.refreshOnFocus();
    expect(fake.actions.where((x) => x == 'load').length, initialReads);
    await controller.refreshOnFocus(DateTime.now().add(const Duration(seconds: 16)));
    expect(fake.actions.where((x) => x == 'load').length, initialReads + 1);
    controller.dispose();
  });

  test('closing flushes pending edits and refuses to silently lose failed saves', () async {
    final fake = RejectSaveScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    controller.edit(instruction: 'Last-moment edit');
    expect(await controller.flushPreferences(), isFalse);
    expect(controller.error, contains('Preferences save could not be confirmed'));
    fake.reject = false;
    expect(await controller.flushPreferences(), isTrue);
    expect((fake.saves.last['draft'] as Map)['message'], 'Last-moment edit');
    expect(controller.error, isNull);
    controller.dispose();
  });

  test('countdown matches WinForms day/hour/minute and UTC instants', () {
    final now = DateTime.utc(2026, 11, 1, 1, 2, 3);
    expect(countdownText(null, now), 'Unknown');
    expect(countdownText(now, now), 'Due now');
    expect(countdownText(now.subtract(const Duration(seconds: 1)), now), 'Due now');
    expect(countdownText(now.add(const Duration(days: 2, hours: 3, minutes: 4)), now), '2d 3h 4m');
    expect(countdownText(now.add(const Duration(hours: 2, minutes: 3)), now), '2h 3m');
    expect(countdownText(now.add(const Duration(minutes: 3, seconds: 4)), now), '3m 4s');
    expect(countdownText(now.add(const Duration(milliseconds: 1)), now), '1s');
  });

  test('countdown fill matches WinForms bounded integer elapsed percentage', () {
    const created = 1793600000;
    final begin = DateTime.fromMillisecondsSinceEpoch(created * 1000, isUtc:true);
    final due = begin.add(const Duration(minutes: 10));
    expect(runElapsedPercent(due, created, begin.subtract(const Duration(seconds:1))), 0);
    expect(runElapsedPercent(due, created, begin.add(const Duration(minutes:5))), 50);
    expect(runElapsedPercent(due, created, due.add(const Duration(minutes:1))), 100);
    final midpointDue = begin.add(const Duration(seconds: 200));
    expect(runElapsedPercent(midpointDue, created, begin.add(const Duration(seconds:1))), 0);
    expect(runElapsedPercent(midpointDue, created, begin.add(const Duration(seconds:3))), 2);
    expect(runElapsedPercent(midpointDue, created, begin.add(const Duration(seconds:5))), 2);
    expect(runElapsedPercent(midpointDue, created, begin.add(const Duration(seconds:7))), 4);
    expect(runElapsedPercent(due, null, begin), isNull);
    expect(runElapsedPercent(due, 0, begin), isNull);
    expect(runElapsedPercent(begin, created, begin), isNull);
  });

  test('packaged worker takes priority over untrusted current directory', () {
    if (!Platform.isWindows) return;
    final sandbox = Directory.systemTemp.createTempSync('flutter-worker-search-');
    addTearDown(() => sandbox.deleteSync(recursive:true));
    final sep = Platform.pathSeparator;
    Directory createSource(String name) {
      final dir = Directory('${sandbox.path}$sep$name')..createSync();
      File('${dir.path}${sep}CodexRunEngine.ps1').createSync();
      File('${dir.path}${sep}flutter_port${sep}windows_bridge.ps1')
        .createSync(recursive:true);
      return dir;
    }
    final bundled = createSource('bundle');
    final untrusted = createSource('cwd');
    final exeDir = Directory('${bundled.path}${sep}bin')..createSync();
    expect(WindowsSchedulerAdapter.findSourceDirectoryFrom(
      executableDirectory: exeDir, workingDirectory: untrusted), bundled.path);
    expect(WindowsSchedulerAdapter.findSourceDirectoryFrom(
      executableDirectory: sandbox, workingDirectory: untrusted), untrusted.path);
    expect(() => WindowsSchedulerAdapter.findSourceDirectoryFrom(
      executableDirectory: sandbox, workingDirectory: untrusted,
      allowWorkingDirectory: false), throwsA(isA<SchedulerException>()));
  });

  test('concurrent saves cannot overwrite a later draft with earlier data', () async {
    final fake = DeferredSaveScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    controller.edit(instruction: 'Earlier preference');
    final first = controller.save();
    await fake.firstSaveEntered.future;
    controller.edit(instruction: 'Latest preference');
    final second = controller.save();
    // The second call is queued until the first disk write is complete.
    expect(fake.maxSimultaneous, 1);
    fake.releaseFirstSave.complete();
    await Future.wait([first, second]);
    expect(fake.maxSimultaneous, 1);
    expect(fake.saves.length, 2);
    expect((fake.saves.last['draft'] as Map)['message'], 'Latest preference');
    controller.dispose();
  });

  test('WinForms parity: restored CLI conversation discovers Git root on startup', () async {
    final fake = StartupRepositoryScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    expect(fake.lookups, 1,
      reason: 'WinForms Apply-SessionList requests repository discovery on startup');
    await controller.selectSession(controller.sessionId);
    expect(controller.repo, r'C:\discovered\checkout');
    await controller.flushPreferences();
    expect((fake.saves.last['draft'] as Map)['repo'], controller.repo);
    controller.dispose();
  });

  test('missing saved conversation selects newest CLI session, not its old root', () async {
    final fake = StartupRepositoryScheduler(
      savedSessionId: '99999999-9999-9999-9999-999999999999',
      savedRepository: r'C:\old\unsafe',
      roots: [r'C:\new\safe'],
    );
    fake.availableSessions = [
      {'Id': '22222222-2222-2222-2222-222222222222',
       'Display': 'Newest CLI project'},
      {'Id': '11111111-1111-1111-1111-111111111111',
       'Display': 'Older CLI project'},
    ];
    final controller = SchedulerController(fake);
    await controller.start();
    expect(controller.sessionId, '22222222-2222-2222-2222-222222222222');
    await controller.selectSession(controller.sessionId);
    expect(controller.repo, r'C:\new\safe');
    expect(controller.repo, isNot(r'C:\old\unsafe'));
    controller.dispose();
  });

  test('saved manual repository wins on startup, with no redundant lookup', () async {
    final fake = StartupRepositoryScheduler(savedRepository: r'C:\manual\verified');
    final controller = SchedulerController(fake);
    await controller.start();
    expect(controller.repo, r'C:\manual\verified');
    expect(fake.lookups, 0);
    controller.dispose();
  });

  test('unresolved startup repository is automatically retried on full refresh', () async {
    final fake = StartupRepositoryScheduler(
      roots: [null, r'C:\recovered\project']);
    final controller = SchedulerController(fake);
    await controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(fake.lookups, 1);
    expect(controller.repo, isEmpty);
    expect(controller.repositoryWarning, contains('unresolved'));
    await controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(fake.lookups, 2);
    expect(controller.repo, r'C:\recovered\project');
    controller.dispose();
  });

  test('refresh loses old session safely and resolves newly selected conversation', () async {
    final fake = StartupRepositoryScheduler(
      savedRepository: r'C:\first\project', roots: [r'C:\second\project']);
    final controller = SchedulerController(fake);
    await controller.start();
    fake.availableSessions = [
      {'Id': '22222222-2222-2222-2222-222222222222',
       'Display': 'Replacement CLI session'},
    ];
    await controller.load();
    await controller.selectSession(controller.sessionId);
    expect(controller.sessionId, '22222222-2222-2222-2222-222222222222');
    expect(controller.repo, r'C:\second\project');
    controller.dispose();
  });

  test('late lookup never fills a repository explicitly cleared by the user', () async {
    final fake = StartupRepositoryScheduler();
    fake.deferredSelection = Completer<Map<String, dynamic>>();
    final controller = SchedulerController(fake);
    await controller.start();
    controller.edit(repository: '');
    fake.deferredSelection!.complete({
      'found': {'Root': r'C:\stale\guessed'},
      'model': 'gpt-test',
    });
    await controller.selectSession(controller.sessionId);
    expect(controller.repo, isEmpty);
    expect(controller.repositoryWarning, isNull);
    controller.dispose();
  });

  test('resolved session repository is automatically persisted', () async {
    final fake = RepositoryLookupScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    await controller.selectSession(null);
    await controller.selectSession('11111111-1111-1111-1111-111111111111');
    expect(controller.repo, r'C:\verified\checkout');
    await Future<void>.delayed(const Duration(milliseconds: 760));
    expect(fake.saves, isNotEmpty);
    expect((fake.saves.last['draft'] as Map)['repo'], r'C:\verified\checkout');
    controller.dispose();
  });

  test('manual repository selection wins over a delayed lookup', () async {
    final fake = PendingRepositoryLookupScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    await controller.selectSession(null);
    final pending = controller.selectSession('11111111-1111-1111-1111-111111111111');
    controller.edit(repository: r'C:\manual\repo');
    fake.lookup.complete({
      'found': {'Root': r'C:\stale\automatic',
        'AlternativeRoots': [r'C:\stale\other']},
      'model': 'gpt-test',
    });
    await pending;
    expect(controller.repo, r'C:\manual\repo');
    expect(controller.repositoryWarning, isNull);
    expect(controller.repositoryAlternatives, isEmpty);
    controller.dispose();
  });

  test('ambiguous repository evidence is visible and manually dismissible', () async {
    final fake = ConflictingRepositoryScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    await controller.selectSession(null);
    await controller.selectSession('11111111-1111-1111-1111-111111111111');
    expect(controller.repo, isEmpty);
    expect(controller.repositoryWarning, contains('Conflicting'));
    expect(controller.repositoryAlternatives, hasLength(2));
    controller.edit(repository: r'C:\verified\chosen');
    expect(controller.repositoryWarning, isNull);
    expect(controller.repositoryAlternatives, isEmpty);
    controller.dispose();
  });

  test('appearance edits auto-save without an explicit Save action', () async {
    final fake = FakeScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    const updated = AeroAppearance(
      quota: 'violet', weekly: 'red', time: '#123ABC',
      working: 'amber', finish: 2, lighting: 1, shimmer: 150,
      speed: 225, aero: false,
    );
    controller.updateAppearance(updated);
    await controller.flushPreferences();
    expect(controller.appearance, updated);
    expect(fake.saves.last['barAppearance'], updated.toJson());
    controller.dispose();
  });

  test('closing the editor persists the last rapid appearance choice', () async {
    final fake = FakeScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    controller.updateAppearance(controller.appearance.copyWith(quota: 'blue'));
    controller.updateAppearance(controller.appearance.copyWith(quota: 'violet'));
    await controller.flushPreferences();
    expect((fake.saves.last['barAppearance'] as Map)['quota'], 'violet');
    await Future<void>.delayed(const Duration(milliseconds: 750));
    expect(fake.saves.length, 1);
    controller.dispose();
  });
}
