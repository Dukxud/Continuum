import 'bridge.dart';

/// The WinForms Countdown component includes minutes even for multi-day
/// countdowns and uses absolute instants to avoid daylight-saving drift.
String countdownText(DateTime? due, [DateTime? now]) {
  if (due == null) return 'Unknown';
  final micros = due
      .toUtc()
      .difference((now ?? DateTime.now()).toUtc())
      .inMicroseconds;
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
  if (due == null ||
      createdAt is! int ||
      !RegExp(r'^\d{9,12}$').hasMatch(createdAt.toString())) {
    return null;
  }
  try {
    final start = DateTime.fromMillisecondsSinceEpoch(
      createdAt * 1000,
      isUtc: true,
    );
    final duration = due.toUtc().difference(start).inMicroseconds;
    if (duration <= 0) return null;
    final elapsed = (now ?? DateTime.now())
        .toUtc()
        .difference(start)
        .inMicroseconds;
    if (elapsed <= 0) return 0;
    if (elapsed >= duration) return 100;
    final scaled = elapsed * 100;
    final whole = scaled ~/ duration;
    final twiceRemainder = 2 * (scaled % duration);
    if (twiceRemainder > duration) return whole + 1;
    if (twiceRemainder < duration) return whole;
    // PowerShell's [Math]::Round defaults to midpoint-to-even, unlike Dart.
    return whole.isEven ? whole : whole + 1;
  } catch (_) {
    return null;
  }
}

/// Windows Task Scheduler accepts local wall-clock time to second precision.
/// Keep the selected seconds instead of silently snapping to whole minutes.
String localIsoSecond(DateTime date) {
  String d(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${d(date.month)}-${d(date.day)}T'
      '${d(date.hour)}:${d(date.minute)}:${d(date.second)}';
}

DateTime suggestedRunAt([DateTime? now]) =>
    (now ?? DateTime.now()).add(const Duration(minutes: 1));
DateTime earliestRunAt([DateTime? now]) =>
    (now ?? DateTime.now()).add(const Duration(seconds: 30));

/// Only an authoritative exhausted-window recommendation activates Reset +1.
/// If it has already elapsed or is invalid, the UI offers Now +1 instead.
DateTime? recommendedResetRunAt(Map<String, dynamic>? quota, [DateTime? now]) {
  if (stringField(quota, 'recommendationKind') != 'exhausted-window') {
    return null;
  }
  final raw = field(quota, 'recommendedResetAt');
  if (raw is! num ||
      !raw.isFinite ||
      raw <= 0 ||
      raw != raw.truncateToDouble()) {
    return null;
  }
  try {
    final reset = DateTime.fromMillisecondsSinceEpoch(raw.toInt() * 1000);
    if (!reset.isAfter(now ?? DateTime.now())) return null;
    return reset.add(const Duration(minutes: 1));
  } catch (_) {
    return null;
  }
}

DateTime stepRunAt(DateTime current, int direction, [DateTime? now]) {
  if (direction != 1 && direction != -1) {
    throw ArgumentError('Invalid direction.');
  }
  final candidate = current.add(Duration(minutes: direction));
  final earliest = earliestRunAt(now);
  if (!candidate.isBefore(earliest)) return candidate;
  return direction == 1 ? earliest : current;
}
