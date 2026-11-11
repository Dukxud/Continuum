import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bridge.dart';

class WindowsSchedulerAdapter implements SchedulerAdapter {
  WindowsSchedulerAdapter({String? sourceDirectory})
    : sourceDirectory = sourceDirectory ?? findSourceDirectory();
  final String sourceDirectory;

  static String findSourceDirectory() {
    final custom = Platform.environment['CODEX_SCHEDULER_SOURCE'];
    if (custom != null && custom.isNotEmpty) {
      if (File('$custom\\src\\backend\\CodexRunEngine.ps1').existsSync()) {
        return custom;
      }
      throw SchedulerException(
        'CODEX_SCHEDULER_SOURCE is not a Scheduler checkout.',
      );
    }
    return findSourceDirectoryFrom(
      executableDirectory: File(Platform.resolvedExecutable).parent.absolute,
      workingDirectory: Directory.current.absolute,
      // Debug `flutter run` relies on checkout CWD. A packaged release must
      // fail closed rather than silently load worker code from CWD.
      allowWorkingDirectory: !const bool.fromEnvironment('dart.vm.product'),
    );
  }

  /// The executable's bundled worker must win over an unrelated current
  /// directory that happens to contain similarly named scripts.
  static String findSourceDirectoryFrom({
    required Directory executableDirectory,
    required Directory workingDirectory,
    bool allowWorkingDirectory = true,
  }) {
    for (final start in [
      executableDirectory,
      if (allowWorkingDirectory) workingDirectory,
    ]) {
      var current = start.absolute;
      for (var depth = 0; depth < 12; depth++) {
        if (File(current.path + r'\src\backend\CodexRunEngine.ps1')
                .existsSync() &&
            File(current.path + r'\src\desktop\windows_bridge.ps1')
                .existsSync()) {
          return current.path;
        }
        if (current.parent.path == current.path) break;
        current = current.parent;
      }
    }
    throw SchedulerException(
      'Run from the Scheduler checkout or set CODEX_SCHEDULER_SOURCE.',
    );
  }

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (!Platform.isWindows) {
      throw SchedulerException('Windows adapter requires Windows.');
    }
    final bridge = sourceDirectory + r'\src\desktop\windows_bridge.ps1';
    if (!File(bridge).existsSync()) {
      throw SchedulerException('Missing Windows adapter: $bridge');
    }
    final executable =
        (Platform.environment['ProgramFiles'] ?? r'C:\Program Files') +
        r'\PowerShell\7\pwsh.exe';
    if (!File(executable).existsSync()) {
      throw SchedulerException('PowerShell 7 is required.');
    }
    final encoded = base64Encode(utf8.encode(jsonEncode(payload)));
    // Process.run(...).timeout() only stops waiting; it leaves a live
    // PowerShell process that could still register/cancel a Windows task.
    // Process.start permits terminating the direct child on timeout.
    Process process;
    try {
      process = await Process.start(executable, [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-STA',
        '-WindowStyle',
        'Hidden',
        '-File',
        bridge,
        '-Action',
        action,
        '-Payload',
        encoded,
      ], workingDirectory: sourceDirectory);
    } catch (error) {
      throw SchedulerException('Unable to start Scheduler adapter: $error');
    }
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    await process.stdin.close();
    late final int exitCode;
    late final String output;
    late final String errors;
    try {
      exitCode = await process.exitCode.timeout(
        action == 'browse'
            ? const Duration(minutes: 10)
            : const Duration(seconds: 55),
      );
      output = await stdout.timeout(const Duration(seconds: 5));
      errors = await stderr.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill();
      throw adapterTimeoutError(action);
    }
    final lines = output
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) throw SchedulerException('No adapter response. $errors');
    Map<String, dynamic> response;
    try {
      response = Map<String, dynamic>.from(jsonDecode(lines.last) as Map);
    } catch (_) {
      throw SchedulerException('Invalid adapter response. $errors');
    }
    if (exitCode != 0 || response['ok'] != true) {
      throw SchedulerException(
        (response['error'] ?? 'Adapter failed.').toString(),
      );
    }
    final body = response['result'];
    return body is Map ? Map<String, dynamic>.from(body) : {'value': body};
  }
}
