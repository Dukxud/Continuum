import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Native Flutter liquid-tube approximation. Does not depend on WebView2/WPF.
class AeroLiquidBar extends StatefulWidget {
  const AeroLiquidBar({super.key, required this.amount, this.tint = const Color(0xff326ea6),
    this.working = false, this.height = 17});
  final double? amount;
  final Color tint;
  final bool working;
  final double height;

  @override
  State<AeroLiquidBar> createState() => _AeroLiquidBarState();
}

class _AeroLiquidBarState extends State<AeroLiquidBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 3200))..repeat();
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final amount = widget.amount?.clamp(0.0, 100.0);
    return Semantics(
      label: widget.working ? 'Codex running, completion unknown' :
          amount == null ? 'Progress unavailable' : '$amount percent',
      child: SizedBox(height: widget.height,
        child: AnimatedBuilder(animation: _controller,
          builder: (context, child) => CustomPaint(
            painter: _AeroPainter(amount: amount, phase: _controller.value,
              tint: widget.tint, working: widget.working),
            size: Size.infinite))),
    );
  }
}

class _AeroPainter extends CustomPainter {
  _AeroPainter({required this.amount, required this.phase,
    required this.tint, required this.working});
  final double? amount;
  final double phase;
  final Color tint;
  final bool working;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(rect.deflate(0.6), radius);
    canvas.drawRRect(track, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xffc4cfde), Color(0xfff6faff), Color(0xffcad7e7)]).createShader(rect));
    canvas.drawRRect(track, Paint()..color = const Color(0xff526984).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke..strokeWidth = 1);
    final fillFraction = working ? 1.0 : (amount ?? 0) / 100;
    if (fillFraction <= 0) return;
    final fillWidth = math.max(2.0, (size.width - 2) * fillFraction);
    final inside = Rect.fromLTWH(1, 1, math.min(fillWidth, size.width - 2), size.height - 2);
    // At exactly 100%, the head is square. Partial heads are droplets.
    final end = working || fillFraction >= 0.99999 ? Radius.zero : radius;
    final fill = RRect.fromRectAndCorners(inside,
      topLeft: radius, bottomLeft: radius, topRight: end, bottomRight: end);
    canvas.save();
    canvas.clipRRect(fill);
    canvas.drawRect(inside, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      stops: const [0, 0.13, 0.47, 0.70, 1],
      colors: [Color.lerp(tint, Colors.white, 0.42)!, tint,
        Color.lerp(tint, Colors.white, 0.18)!,
        Color.lerp(tint, Colors.black, 0.10)!,
        Color.lerp(tint, Colors.black, 0.35)!]).createShader(inside));
    final glint = Rect.fromLTWH(-size.width * 0.4 + phase * size.width * 1.75,
      -size.height, size.width * 0.46, size.height * 3);
    canvas.save();
    canvas.translate(glint.center.dx, glint.center.dy);
    canvas.rotate(-0.28);
    canvas.translate(-glint.center.dx, -glint.center.dy);
    canvas.drawOval(glint, Paint()..shader = RadialGradient(
      colors: [Colors.white.withValues(alpha: 0.65),
        Colors.white.withValues(alpha: 0)]).createShader(glint));
    canvas.restore();
    final shine = Rect.fromLTWH(inside.left, 1, inside.width, (size.height - 2) * 0.43);
    canvas.drawRRect(RRect.fromRectAndRadius(shine, radius),
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: 0.65),
          Colors.white.withValues(alpha: 0.02)]).createShader(shine));
    canvas.restore();
    canvas.drawRRect(fill, Paint()..color = tint.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke..strokeWidth = 0.7);
  }
  @override
  bool shouldRepaint(covariant _AeroPainter oldDelegate) =>
    oldDelegate.amount != amount || oldDelegate.tint != tint ||
    oldDelegate.phase != phase || oldDelegate.working != working;
}
