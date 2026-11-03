import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/scheduler_controller.dart';

class FakeScheduler implements SchedulerAdapter {
  final List<String> actions = [];
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
        return {'saved': true};
      default:
        return {};
    }
  }
}

void main() {
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
}
