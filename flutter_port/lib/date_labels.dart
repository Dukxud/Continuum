/// Presentation-only date formats. Local scheduling times are intentionally
/// kept separate from Windows' exact-second wire protocol.
const _monthAbbreviations = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatDayMonth(DateTime value, {bool year = false}) {
  final date = '${value.day} ${_monthAbbreviations[value.month - 1]}';
  return year ? '$date ${value.year}' : date;
}

String formatLocalDateTime(DateTime value, {
  bool year = false,
  bool seconds = false,
}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final clock = '$hour:${two(value.minute)}'
      '${seconds ? ':${two(value.second)}' : ''}'
      '${value.hour >= 12 ? ' PM' : ' AM'}';
  return '${formatDayMonth(value, year: year)} · $clock';
}
