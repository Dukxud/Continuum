import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/main.dart';
import 'package:codex_resume_flutter/bridge.dart';

class StubAdapter implements SchedulerAdapter {
  @override
  Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> payload = const {}]) async {
    if (action == 'load') {
      return {'sessions': [], 'pending': [], 'history': [],
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
  testWidgets('Windows Flutter entry exposes controls without registering a job', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(adapter: StubAdapter())));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('CODEX RESUME SCHEDULER'), findsOneWidget);
    expect(find.text('Schedule once'), findsOneWidget);
    expect(find.text('Recent runs'), findsOneWidget);
    expect(find.text('USAGE REMAINING'), findsOneWidget);
  });
}
