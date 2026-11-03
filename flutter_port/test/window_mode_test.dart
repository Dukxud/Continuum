import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/bridge.dart';
import 'package:codex_resume_flutter/desktop_window.dart';
import 'package:codex_resume_flutter/main.dart';

class SpyWindowHost implements SchedulerWindowHost {
  final List<String> modes = [];
  @override
  Future<void> setMode({required bool compact, required bool hasRun}) async {
    modes.add((compact ? 'compact' : 'standard') + (hasRun ? ':run' : ':empty'));
  }
  @override
  Future<void> showDialogWindow({required bool history}) async {}
  @override
  Future<void> restoreMode({required bool compact, required bool hasRun}) async {
    await setMode(compact: compact, hasRun: hasRun);
  }
}

class WindowAdapter implements SchedulerAdapter {
  WindowAdapter({required this.startCompact, this.hasRun = false});
  final bool startCompact;
  final bool hasRun;
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
        'windows': [], 'ordinaryUsageAllowed': true,
        'accountId': 'workspace-sha256:' + 'a' * 64};
    }
    if (action == 'pending') {
      return {'pending': [], 'history': []};
    }
    return {};
  }
}

void main() {
  testWidgets('compact mode changes the host window size, not only controls', (tester) async {
    final host = SpyWindowHost();
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: false),
      windowHost: host)));
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.modes, contains('standard:empty'));
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.modes, contains('compact:empty'));
    expect(find.text('Schedule once'), findsNothing);
    expect(find.text('USAGE REMAINING'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved compact preference opens a compact window', (tester) async {
    final host = SpyWindowHost();
    await tester.pumpWidget(MaterialApp(home: SchedulerHome(
      adapter: WindowAdapter(startCompact: true),
      windowHost: host)));
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.modes.first, 'compact:empty');
    expect(tester.takeException(), isNull);
  });
}
