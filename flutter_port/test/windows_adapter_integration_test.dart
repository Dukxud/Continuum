import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/bridge.dart';

void main() {
  test('Windows Dart adapter invokes the real read-only PowerShell JSON bridge', () async {
    if (!Platform.isWindows) return;
    // This exercises the actual Process.start/exit/stdout protocol, not a
    // fake adapter. It reads task/history data only and cannot schedule jobs.
    final result = await WindowsSchedulerAdapter().call('pending');
    expect(result['pending'], isA<List>());
    expect(result['history'], isA<List>());
  });
}
