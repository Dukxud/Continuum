import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'bridge.dart';

class WindowsSchedulerAdapter implements SchedulerAdapter {
  WindowsSchedulerAdapter({String? sourceDirectory})
    : sourceDirectory = sourceDirectory == null
          ? findSourceDirectory()
          : _resolveExplicitSource(
              sourceDirectory,
              Directory.current.absolute,
              'sourceDirectory',
            );
  final String sourceDirectory;

  static String findSourceDirectory() {
    return findSourceDirectoryFrom(
      executableDirectory: File(Platform.resolvedExecutable).parent.absolute,
      workingDirectory: Directory.current.absolute,
      sourceOverride: Platform.environment['CODEX_SCHEDULER_SOURCE'],
      // Debug `flutter run` relies on checkout CWD. A packaged release must
      // use only its adjacent bundle unless an override is explicit.
      allowWorkingDirectory: !const bool.fromEnvironment('dart.vm.product'),
    );
  }

  static bool _containsBackend(Directory directory) =>
      File.fromUri(directory.uri.resolve('src/backend/CodexRunEngine.ps1'))
          .existsSync() &&
      File.fromUri(directory.uri.resolve('src/desktop/windows_bridge.ps1'))
          .existsSync();

  static String _resolveExplicitSource(
    String supplied,
    Directory workingDirectory,
    String label,
  ) {
    Directory? resolved;
    if (supplied.trim().isNotEmpty) {
      try {
        // Keep relative overrides relative to the caller's CWD, as before,
        // then store an absolute path before the bridge changes its own CWD.
        resolved = Directory.fromUri(
          workingDirectory.absolute.uri.resolveUri(Directory(supplied).uri),
        ).absolute;
        if (resolved.path.endsWith(Platform.pathSeparator) &&
            resolved.parent.path != resolved.path) {
          resolved = Directory(
            resolved.path.substring(0, resolved.path.length - 1),
          );
        }
      } on ArgumentError {
        resolved = null;
      }
    }
    if (resolved == null || !_containsBackend(resolved)) {
      throw SchedulerException(
        '$label must point to a complete Continuum backend containing '
        'src/backend/CodexRunEngine.ps1 and src/desktop/windows_bridge.ps1.'
        '${resolved == null ? '' : ' Resolved directory: ${resolved.path}'}',
      );
    }
    return resolved.path;
  }

  /// Release discovery is confined to the executable directory. Debug discovery
  /// may walk checkout ancestors and the working directory used by flutter run.
  static String findSourceDirectoryFrom({
    required Directory executableDirectory,
    required Directory workingDirectory,
    String? sourceOverride,
    bool allowWorkingDirectory = true,
  }) {
    if (sourceOverride != null && sourceOverride.isNotEmpty) {
      return _resolveExplicitSource(
        sourceOverride,
        workingDirectory,
        'CODEX_SCHEDULER_SOURCE',
      );
    }
    if (!allowWorkingDirectory) {
      final bundled = executableDirectory.absolute;
      if (_containsBackend(bundled)) return bundled.path;
      throw SchedulerException(
        'The complete Continuum application package must be beside the '
        'executable. Extract the full package, or set CODEX_SCHEDULER_SOURCE '
        'to a complete backend.',
      );
    }
    for (final start in [executableDirectory, workingDirectory]) {
      var current = start.absolute;
      for (var depth = 0; depth < 12; depth++) {
        if (_containsBackend(current)) return current.path;
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
    final bridge = File.fromUri(
      Directory(sourceDirectory).uri.resolve('src/desktop/windows_bridge.ps1'),
    ).path;
    if (!File(bridge).existsSync()) {
      throw SchedulerException('Missing Windows adapter: $bridge');
    }
    final executable = resolveWindowsPowerShell(
      pathDirectories: (Platform.environment['PATH'] ?? '').split(';'),
      programW6432Directory: Platform.environment['ProgramW6432'],
      programFilesDirectory: Platform.environment['ProgramFiles'],
    );
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

/// Use the same installed PowerShell selected by the root launcher's PATH.
/// Native Program Files precedes an inherited 32-bit Program Files fallback.
/// This filesystem-only resolver can be tested without starting Windows code.
String resolveWindowsPowerShell({
  required Iterable<String> pathDirectories,
  String? programW6432Directory,
  String? programFilesDirectory,
}) {
  final directories = <String>[...pathDirectories];
  for (final root in [programW6432Directory, programFilesDirectory]) {
    if (root != null && root.isNotEmpty) {
      directories.add(
        Directory(root).uri.resolve('PowerShell/7/').toFilePath(),
      );
    }
  }
  final seen = <String>{};
  for (var path in directories) {
    path = path.trim();
    if (path.length >= 2 && path.startsWith('"') && path.endsWith('"')) {
      path = path.substring(1, path.length - 1);
    }
    if (path.isEmpty || !Directory(path).isAbsolute) continue;
    final directory = Directory(path);
    if (!seen.add(directory.path.toLowerCase())) continue;
    final executable = File.fromUri(directory.uri.resolve('pwsh.exe'));
    if (executable.existsSync()) return executable.path;
  }
  throw SchedulerException(
    'PowerShell 7.4 or newer is required. Install it or add pwsh.exe to PATH, '
    'then restart Continuum.',
  );
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
