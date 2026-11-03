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
      expect(find.text('CODEX RESUME SCHEDULER'), findsOneWidget);
      expect(find.text('Schedule once'), findsOneWidget);
      expect(find.text('USAGE REMAINING'), findsOneWidget);
      expect(find.textContaining('UPCOMING RUNS'), findsOneWidget);
      await tester.ensureVisible(find.text('Recent runs'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
