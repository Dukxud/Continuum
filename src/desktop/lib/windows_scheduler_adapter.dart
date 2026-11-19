import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    return invokeSchedulerProcess(
      action,
      executable: executable,
      arguments: [
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
      ],
      workingDirectory: sourceDirectory,
    );
  }
}

/// The production subprocess boundary, separate from Windows installation
/// discovery so read-only bridge calls can be verified with real child processes.
Future<Map<String, dynamic>> invokeSchedulerProcess(
  String action, {
  required String executable,
  required List<String> arguments,
  required String workingDirectory,
  Map<String, String>? environment,
  Duration? responseTimeout,
}) async {
  // Process.run(...).timeout() only stops waiting; it leaves a live
  // PowerShell process that could still register/cancel a Windows task.
  // Process.start permits terminating the direct child on timeout.
  Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  } on ProcessException catch (error) {
    // ProcessException.toString includes the argument list, which can contain
    // an encoded user instruction. Report the OS error without the payload.
    throw SchedulerException(
      'Unable to start Scheduler $action adapter: ${error.message}',
    );
  }
  // Attach handlers to all streams immediately. Decoding before exit was
  // awaited could raise an unhandled FormatException in the meantime. Stderr
  // is diagnostic output, not part of the JSON contract; drain it as bytes.
  final completed = Future.wait<Object?>([
    process.exitCode,
    process.stdout.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (buffer, bytes) => buffer..add(bytes),
    ),
    process.stderr.drain<void>(),
    process.stdin.close(),
  ], eagerError: true);
  late final List<Object?> values;
  try {
    values = await completed.timeout(
      responseTimeout ??
          (action == 'browse'
              ? const Duration(minutes: 10)
              : const Duration(seconds: 55)),
    );
  } on TimeoutException {
    process.kill();
    throw adapterTimeoutError(action);
  } on IOException catch (error) {
    process.kill();
    throw SchedulerException(
      'Scheduler $action transport failed (${error.runtimeType}). '
      'Source: $workingDirectory',
    );
  }
  final exitCode = values[0] as int;
  late final String output;
  try {
    output = utf8.decode((values[1] as BytesBuilder).takeBytes());
  } on FormatException {
    throw SchedulerException(
      'Invalid UTF-8 in Scheduler $action response (exit $exitCode). '
      'Source: $workingDirectory',
    );
  }
  final lines = output
      .split(RegExp(r'\r?\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    throw SchedulerException(
      'No Scheduler $action response (exit $exitCode). '
      'Source: $workingDirectory',
    );
  }
  Map<String, dynamic> response;
  try {
    response = Map<String, dynamic>.from(jsonDecode(lines.last) as Map);
  } catch (_) {
    throw SchedulerException(
      'Invalid Scheduler $action JSON response (exit $exitCode). '
      'Source: $workingDirectory',
    );
  }
  if (exitCode != 0 || response['ok'] != true) {
    throw SchedulerException(
      (response['error'] ??
              'Scheduler $action adapter failed (exit $exitCode).')
          .toString(),
    );
  }
  final body = response['result'];
  return body is Map ? Map<String, dynamic>.from(body) : {'value': body};
}
