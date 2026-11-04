import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'aero_appearance.dart';

/// The exact approved Aero v3 GLSL fragment program is in shaders/aero_liquid.frag.
/// These source-pixel PNGs are extracted unchanged from assets/AeroBar.html.
///
/// Native v1.8 source pixels are always drawn first; Flutter/Impeller then
/// composites the ported liquid optics using the same 15-float uniform contract.
/// If GPU shaders are unavailable, the original sprite remains functional.
class AeroAssets {
  AeroAssets._();
  static Future<Map<String, ui.Image>>? _spriteLoad;
  static Future<ui.FragmentProgram?>? _opticalLoad;
  static String? shaderError;

  static Future<Map<String, ui.Image>> sprites() {
    return _spriteLoad ??= _readSprites();
  }

  static Future<Map<String, ui.Image>> _readSprites() async {
    final images = <String, ui.Image>{};
    for (final name in AeroAppearance.presetColors.keys) {
      final bytes = await rootBundle.load('assets/native/' + name + '.png');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      try {
        final frame = await codec.getNextFrame();
        images[name] = frame.image;
      } finally {
        codec.dispose();
      }
    }
    return images;
  }

  static Future<ui.FragmentProgram?> shader() {
    return _opticalLoad ??= _readShader();
  }

  static Future<ui.FragmentProgram?> _readShader() async {
    try {
      shaderError = null;
      return await ui.FragmentProgram.fromAsset('shaders/aero_liquid.frag');
    } catch (error) {
      shaderError = error.toString();
      return null;
    }
  }
}

class AeroLiquidBar extends StatefulWidget {
  const AeroLiquidBar({
    super.key,
    required this.amount,
    required this.appearance,
    required this.kind,
    this.working = false,
    this.height = 17,
  });

  /// Percent of remaining capacity or elapsed countdown; null is unknown.
  final double? amount;
  final AeroAppearance appearance;
  final String kind;
  final bool working;
  final double height;

  @override
  State<AeroLiquidBar> createState() => _AeroLiquidBarState();
}

class _AeroLiquidBarState extends State<AeroLiquidBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  Map<String, ui.Image>? _sprites;
  ui.FragmentProgram? _shaderProgram;
  double _visible = 0;
  bool _initializedValue = false;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this, duration: const Duration(seconds: 100),
      value: math.Random().nextDouble(),
    )..repeat();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await Future.wait<Object?>([
        AeroAssets.sprites(),
        AeroAssets.shader(),
      ]);
      if (!mounted) return;
      setState(() {
        _sprites = loaded[0] as Map<String, ui.Image>;
        _shaderProgram = loaded[1] as ui.FragmentProgram?;
      });
    } catch (_) {
      // Flutter's non-GPU test harness and unavailable assets retain the
      // deterministic native fallback drawn by _AeroPainter.
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.working ? 100.0 : widget.amount?.clamp(0, 100).toDouble();
    final title = widget.working
      ? 'Codex running; completion is unknown'
      : target == null ? 'Progress unavailable'
      : target.toStringAsFixed(1) + ' percent';

    return Semantics(label: title, child: SizedBox(height: widget.height,
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, child) {
          if (target != null) {
            if (!_initializedValue || widget.working || target == 100) {
              _visible = target;
              _initializedValue = true;
            } else {
              final delta = target - _visible;
              _visible = delta.abs() < 0.002 ? target : _visible + delta * .13;
            }
          } else {
            _initializedValue = false;
            _visible = 0;
          }
          return CustomPaint(
            size: Size.infinite,
            painter: _AeroPainter(
              percent: target,
              visible: widget.working ? 100 : _visible,
              source: _sprites,
              shaderProgram: _shaderProgram,
              appearance: widget.appearance,
              kind: widget.kind,
              working: widget.working,
              seconds: _clock.value * 100,
            ),
          );
        },
      ),
    ));
  }
}

class _AeroPainter extends CustomPainter {
  _AeroPainter({
    required this.percent,
    required this.visible,
    required this.source,
    required this.shaderProgram,
    required this.appearance,
    required this.kind,
    required this.working,
    required this.seconds,
  });

  final double? percent;
  final double visible;
  final Map<String, ui.Image>? source;
  final ui.FragmentProgram? shaderProgram;
  final AeroAppearance appearance;
  final String kind;
  final bool working;
  final double seconds;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 2 || size.height < 2) return;
    final bounds = Offset.zero & size;
    final baseColor = appearance.color(kind);
    final choice = appearance.selection(kind);
    final srcName = AeroAppearance.presetColors.containsKey(choice)
        ? choice : 'green';
    final original = source?[srcName];
    if (original == null) {
      _fallback(canvas, size, baseColor);
    } else {
      _paintSprite(canvas, size, original);
    }
    if (!appearance.aero || percent == null || shaderProgram == null) return;

    // uRes.xy, uFill, uTime, uVel, uFinish, uLights,
    // uLightBackground, uDepth, uCompact, uShimmer, uWorking, uAccent.xyz.
    // This order matches the approved shader's declarations exactly.
    final shader = shaderProgram!.fragmentShader();
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, (visible / 100).clamp(0, 1).toDouble());
    shader.setFloat(3, seconds * appearance.speed / 100.0);
    shader.setFloat(4, 0);
    shader.setFloat(5, appearance.finish.toDouble());
    shader.setFloat(6, appearance.lighting.toDouble());
    shader.setFloat(7, 0);
    shader.setFloat(8, 1);
    shader.setFloat(9, 0);
    shader.setFloat(10, appearance.shimmer / 100.0);
    shader.setFloat(11, working ? 1 : 0);
    // The default accent RGB values are retained from the original shader.
    final rgb = _shaderRgb(choice, baseColor);
    shader.setFloat(12, rgb[0]);
    shader.setFloat(13, rgb[1]);
    shader.setFloat(14, rgb[2]);
    canvas.drawRect(bounds, Paint()..shader = shader);
  }

  List<double> _shaderRgb(String choice, Color color) {
    switch (choice) {
      case 'green': return [.030, .87, .37];
      case 'blue': return [.025, .33, 1.0];
      case 'cyan': return [.015, .81, 1.0];
      case 'violet': return [.47, .22, 1.0];
      case 'amber': return [1.0, .47, .035];
      case 'red': return [1.0, .045, .14];
      default: return [
        math.pow(color.r, 1.09).toDouble(),
        math.pow(color.g, 1.09).toDouble(),
        math.pow(color.b, 1.09).toDouble(),
      ];
    }
  }

  void _paintSprite(Canvas canvas, Size size, ui.Image sprite) {
    final bounds = Offset.zero & size;
    final trackSource = const Rect.fromLTWH(280, 0, 110, 13);
    const paint = FilterQuality.none;
    canvas.drawImageRect(sprite, trackSource, bounds,
      Paint()..filterQuality = paint);

    final f = (visible / 100).clamp(0, 1).toDouble();
    final side = math.max(1.0, size.width / 400);
    final vertical = math.max(1.0, size.height / 13);
    final tip = f >= .999999
      ? size.width - side
      : (f * size.width - 2 * size.width / 400).clamp(side, size.width - side).toDouble();
    final length = tip - side;
    if (f > 0 && length > 0) {
      final path = Path();
      if (!appearance.aero || f >= .999999) {
        path.addRect(Rect.fromLTWH(side, vertical, length, size.height - vertical * 2));
      } else {
        final r = (size.height - 2 * vertical) / 2;
        if (length < 2 * r) {
          final rx = length / 2;
          path.addOval(Rect.fromCenter(
            center: Offset((side + tip) / 2, size.height / 2),
            width: length, height: math.min(rx * 2, r * 2)));
        } else {
          path.addRRect(RRect.fromRectAndCorners(
            Rect.fromLTWH(side, vertical, length, size.height - vertical * 2),
            topLeft: Radius.zero, bottomLeft: Radius.zero,
            topRight: Radius.circular(r), bottomRight: Radius.circular(r)));
        }
      }
      canvas.save();
      canvas.clipPath(path);
      // This is the original v1.8 pixel capture; the fill and track stay
      // aligned to the same inset as the optical GLSL.
      final fillSource = const Rect.fromLTWH(5, 1, 190, 11);
      final destination = Rect.fromLTWH(side, vertical, length, size.height - vertical * 2);
      final fillPaint = Paint()..filterQuality = FilterQuality.none;
      if (!AeroAppearance.presetColors.containsKey(appearance.selection(kind))) {
        fillPaint.colorFilter = ColorFilter.mode(
          appearance.color(kind), BlendMode.srcATop);
      }
      canvas.drawImageRect(sprite, fillSource, destination, fillPaint);
      canvas.restore();
    }
    canvas.drawImageRect(sprite, const Rect.fromLTWH(0, 0, 1, 13),
      Rect.fromLTWH(0, 0, side, size.height), Paint()..filterQuality = paint);
    canvas.drawImageRect(sprite, const Rect.fromLTWH(399, 0, 1, 13),
      Rect.fromLTWH(size.width - side, 0, side, size.height),
      Paint()..filterQuality = paint);
    // Approved Windows source softens terminal columns only AFTER restoring
    // both original source-pixel edges; retaining the black caps is not parity.
    final endCap = Paint()..color = appearance.selection(kind) == 'blue'
      ? const Color(0xffb4c8e5) : const Color(0xffb3cfc2);
    canvas.drawRect(Rect.fromLTWH(0, 0, side, size.height), endCap);
    canvas.drawRect(Rect.fromLTWH(size.width-side, 0, side, size.height), endCap);
  }

  void _fallback(Canvas canvas, Size size, Color tint) {
    final bounds = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(9)),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xffbac9db), Color(0xfff6faff), Color(0xffbac9db)])
        .createShader(bounds));
    final f = ((working ? 100.0 : visible) / 100).clamp(0, 1).toDouble();
    if (f <= 0) return;
    final fill = Rect.fromLTWH(1, 1, (size.width - 2) * f, size.height - 2);
    final end = f >= 1 ? Radius.zero : Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndCorners(fill,
      topLeft: Radius.circular(size.height / 2),
      bottomLeft: Radius.circular(size.height / 2),
      topRight: end, bottomRight: end),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color.lerp(tint, Colors.white, .55)!,
          tint, Color.lerp(tint, Colors.black, .25)!]).createShader(fill));
  }

  @override
  bool shouldRepaint(covariant _AeroPainter oldDelegate) =>
    oldDelegate.percent != percent || oldDelegate.visible != visible ||
    oldDelegate.source != source || oldDelegate.shaderProgram != shaderProgram ||
    oldDelegate.appearance != appearance || oldDelegate.kind != kind ||
    oldDelegate.working != working || oldDelegate.seconds != seconds;
}
