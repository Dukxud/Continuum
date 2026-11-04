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

  test('appearance Cancel cannot leak into concurrent preference saves', () async {
    final fake = FakeScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    final baseline = controller.appearance;
    controller.beginAppearancePreview();
    controller.previewAppearance(baseline.copyWith(
      quota: '#123ABC', weekly: 'violet', shimmer: 180));
    await controller.save();
    final snapshot = fake.saves.last['barAppearance'] as Map<String, dynamic>;
    expect(snapshot['quota'], baseline.quota);
    expect(snapshot['weekly'], baseline.weekly);
    expect(snapshot['shimmer'], baseline.shimmer);
    controller.cancelAppearancePreview();
    expect(controller.appearance, baseline);
    controller.dispose();
  });

  test('appearance Save commits all nine compatible settings', () async {
    final fake = FakeScheduler();
    final controller = SchedulerController(fake);
    await controller.start();
    controller.beginAppearancePreview();
    const updated = AeroAppearance(
      quota: 'violet', weekly: 'red', time: '#123ABC',
      working: 'amber', finish: 2, lighting: 1, shimmer: 150,
      speed: 225, aero: false,
    );
    controller.commitAppearance(updated);
    await controller.save();
    expect(controller.appearance, updated);
    final snapshot = fake.saves.last['barAppearance'];
    expect(snapshot, updated.toJson());
    controller.dispose();
  });
}
