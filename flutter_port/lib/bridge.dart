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
    final candidates = <Directory>[
      Directory.current.absolute,
      File(Platform.resolvedExecutable).parent.absolute,
    ];
    for (final start in candidates) {
      var current = start;
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
    ProcessResult result;
    try {
      result = await Process.run(
        executable,
        ['-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-WindowStyle',
         'Hidden', '-File', bridge, '-Action', action, '-Payload', encoded],
        workingDirectory: sourceDirectory,
      ).timeout(const Duration(seconds: 55));
    } catch (error) {
      throw SchedulerException('Scheduler adapter did not respond: $error');
    }
    final lines = result.stdout.toString().split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) throw SchedulerException('No adapter response. ' + result.stderr.toString());
    Map<String, dynamic> response;
    try {
      response = Map<String, dynamic>.from(jsonDecode(lines.last) as Map);
    } catch (_) {
      throw SchedulerException('Invalid adapter response. ' + result.stderr.toString());
    }
    if (result.exitCode != 0 || response['ok'] != true) {
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
