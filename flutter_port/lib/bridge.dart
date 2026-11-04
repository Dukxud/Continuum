import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Platform boundary. This first adapter preserves the verified Windows
/// worker rather than duplicating security-sensitive scheduling rules.
abstract class SchedulerAdapter {
  Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> payload = const {}]);
}

class SchedulerException implements Exception {
  SchedulerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The underlying Windows action may have completed despite a transport timeout.
/// Callers must not imply that retrying is safe until outcomes are reconciled.
class SchedulerOutcomeUncertain extends SchedulerException {
  SchedulerOutcomeUncertain(super.message);
}

SchedulerException adapterTimeoutError(String action) {
  const mutations = {'schedule', 'cancel', 'save', 'hide'};
  if (mutations.contains(action)) {
    return SchedulerOutcomeUncertain(
      'Outcome uncertain: $action exceeded the response limit. '
      'Check Windows Scheduler and recent results before retrying.');
  }
  return SchedulerException('Scheduler $action request timed out.');
}

class WindowsSchedulerAdapter implements SchedulerAdapter {
  WindowsSchedulerAdapter({String? sourceDirectory})
      : sourceDirectory = sourceDirectory ?? findSourceDirectory();
  final String sourceDirectory;

  static String findSourceDirectory() {
    final custom = Platform.environment['CODEX_SCHEDULER_SOURCE'];
    if (custom != null && custom.isNotEmpty) {
      if (File('$custom\\CodexRunEngine.ps1').existsSync()) return custom;
      throw SchedulerException('CODEX_SCHEDULER_SOURCE is not a Scheduler checkout.');
    }
    return findSourceDirectoryFrom(
      executableDirectory: File(Platform.resolvedExecutable).parent.absolute,
      workingDirectory: Directory.current.absolute,
    );
  }

  /// The executable's bundled worker must win over an unrelated current
  /// directory that happens to contain similarly named scripts.
  static String findSourceDirectoryFrom({
    required Directory executableDirectory,
    required Directory workingDirectory,
  }) {
    for (final start in [executableDirectory, workingDirectory]) {
      var current = start.absolute;
      for (var depth = 0; depth < 12; depth++) {
        if (File(current.path + r'\CodexRunEngine.ps1').existsSync() &&
            File(current.path + r'\flutter_port\windows_bridge.ps1').existsSync()) {
          return current.path;
        }
        if (current.parent.path == current.path) break;
        current = current.parent;
      }
    }
    throw SchedulerException('Run from the Scheduler checkout or set CODEX_SCHEDULER_SOURCE.');
  }

  @override
  Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> payload = const {}]) async {
    if (!Platform.isWindows) throw SchedulerException('Windows adapter requires Windows.');
    final bridge = sourceDirectory + r'\flutter_port\windows_bridge.ps1';
    if (!File(bridge).existsSync()) throw SchedulerException('Missing Windows adapter: $bridge');
    final executable = (Platform.environment['ProgramFiles'] ?? r'C:\Program Files') +
        r'\PowerShell\7\pwsh.exe';
    if (!File(executable).existsSync()) throw SchedulerException('PowerShell 7 is required.');
    final encoded = base64Encode(utf8.encode(jsonEncode(payload)));
    // Process.run(...).timeout() only stops waiting; it leaves a live
    // PowerShell process that could still register/cancel a Windows task.
    // Process.start permits terminating the direct child on timeout.
    Process process;
    try {
      process = await Process.start(
        executable,
        ['-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-WindowStyle',
         'Hidden', '-File', bridge, '-Action', action, '-Payload', encoded],
        workingDirectory: sourceDirectory,
      );
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
          : const Duration(seconds: 55));
      output = await stdout.timeout(const Duration(seconds: 5));
      errors = await stderr.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill();
      throw adapterTimeoutError(action);
    }
    final lines = output.split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) throw SchedulerException('No adapter response. $errors');
    Map<String, dynamic> response;
    try {
      response = Map<String, dynamic>.from(jsonDecode(lines.last) as Map);
    } catch (_) {
      throw SchedulerException('Invalid adapter response. $errors');
    }
    if (exitCode != 0 || response['ok'] != true) {
      throw SchedulerException((response['error'] ?? 'Adapter failed.').toString());
    }
    final body = response['result'];
    return body is Map ? Map<String, dynamic>.from(body) : {'value': body};
  }
}

List<Map<String, dynamic>> recordList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
}

dynamic field(Map<String, dynamic>? row, String key) {
  if (row == null) return null;
  if (row.containsKey(key)) return row[key];
  for (final entry in row.entries) {
    if (entry.key.toLowerCase() == key.toLowerCase()) return entry.value;
  }
  return null;
}

String stringField(Map<String, dynamic>? row, String key) =>
    field(row, key)?.toString() ?? '';

DateTime? dateField(Map<String, dynamic>? row, String key) {
  final raw = field(row, key);
  if (raw == null) return null;
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
  return DateTime.tryParse(raw.toString())?.toLocal();
}

/// The WinForms Countdown component includes minutes even for multi-day
/// countdowns and uses absolute instants to avoid daylight-saving drift.
String countdownText(DateTime? due, [DateTime? now]) {
  if (due == null) return 'Unknown';
  final micros = due.toUtc().difference((now ?? DateTime.now()).toUtc()).inMicroseconds;
  if (micros <= 0) return 'Due now';
  final seconds = (micros + 999999) ~/ 1000000;
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  if (days > 0) return '${days}d ${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${remainder}s';
  return '${remainder}s';
}

/// Preserve the WinForms integer (0–100) elapsed fraction, or unknown.
int? runElapsedPercent(DateTime? due, Object? createdAt, [DateTime? now]) {
  if (due == null || createdAt is! int ||
      !RegExp(r'^\d{9,12}$').hasMatch(createdAt.toString())) return null;
  try {
    final start = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000, isUtc: true);
    final duration = due.toUtc().difference(start).inMicroseconds;
    if (duration <= 0) return null;
    final elapsed = (now ?? DateTime.now()).toUtc().difference(start).inMicroseconds;
    return (100.0 * elapsed / duration).clamp(0.0, 100.0).round();
  } catch (_) {
    return null;
  }
}

String localIsoMinute(DateTime date) {
  String d(int value) => value.toString().padLeft(2, '0');
  return date.year.toString() + '-' + d(date.month) + '-' + d(date.day) +
      'T' + d(date.hour) + ':' + d(date.minute) + ':00';
}

DateTime nextWholeMinute(DateTime date) {
  final base = DateTime(date.year, date.month, date.day, date.hour, date.minute);
  return base.isBefore(date) ? base.add(const Duration(minutes: 1)) : base;
}
DateTime suggestedRunAt([DateTime? now]) =>
    nextWholeMinute((now ?? DateTime.now()).add(const Duration(minutes: 2)));
DateTime earliestRunAt([DateTime? now]) =>
    nextWholeMinute((now ?? DateTime.now()).add(const Duration(seconds: 30)));
DateTime stepRunAt(DateTime current, int direction, [DateTime? now]) {
  if (direction != 1 && direction != -1) throw ArgumentError('Invalid direction.');
  final candidate = current.add(Duration(minutes: direction));
  final earliest = earliestRunAt(now);
  if (!candidate.isBefore(earliest)) return candidate;
  return direction == 1 ? earliest : current;
}
