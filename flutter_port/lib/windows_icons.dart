import 'package:flutter/material.dart';

/// Windows-like affordances painted from geometry rather than a platform font.
/// This makes the same controls readable in native Impeller and test captures.
class WindowsCaret extends StatelessWidget {
  const WindowsCaret({super.key, this.color = const Color(0xff253a58)});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 15, height: 14,
    child: CustomPaint(painter: _CaretPainter(color)),
  );
}

class _CaretPainter extends CustomPainter {
  const _CaretPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.width / 2;
    final y = size.height / 2 - 1;
    canvas.drawPath(Path()
      ..moveTo(middle - 4, y)
      ..lineTo(middle + 4, y)
      ..lineTo(middle, y + 4)
      ..close(),
      Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CaretPainter old) => color != old.color;
}

class WindowsCalendarGlyph extends StatelessWidget {
  const WindowsCalendarGlyph({super.key,
    this.color = const Color(0xff516f98)});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 17, height: 17,
    child: CustomPaint(painter: _CalendarPainter(color)),
  );
}

class _CalendarPainter extends CustomPainter {
  const _CalendarPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(const Rect.fromLTWH(2.5, 3.5, 12, 11), stroke);
    canvas.drawLine(const Offset(3, 7), const Offset(14, 7), stroke);
    canvas.drawLine(const Offset(6, 2), const Offset(6, 5), stroke);
    canvas.drawLine(const Offset(11, 2), const Offset(11, 5), stroke);
    final date = Paint()..color = color.withValues(alpha: .65);
    for (final y in [9.0, 12.0]) {
      for (final x in [5.0, 8.0, 11.0]) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1.5, 1.5), date);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CalendarPainter old) => color != old.color;
}
