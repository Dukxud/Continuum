/// Platform boundary. This first adapter preserves the verified Windows
/// worker rather than duplicating security-sensitive scheduling rules.
abstract class SchedulerAdapter {
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]);
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
      'Check Windows Scheduler and recent results before retrying.',
    );
  }
  return SchedulerException('Scheduler $action request timed out.');
}

List<Map<String, dynamic>> recordList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
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
