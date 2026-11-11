import 'package:flutter/material.dart';

/// The visual system is independent of the privileged Windows adapter.
abstract final class DeckColor {
  static const voidInk = Color(0xff090d19);
  static const deepInk = Color(0xff11182b);
  static const text = Color(0xfff5f5fc);
  static const muted = Color(0xffa8b6d0);
  static const subtle = Color(0xff7483a4);
  static const line = Color(0xff38445d);
  static const coral = Color(0xffff8b65);
  static const gold = Color(0xffffd48b);
  static const mint = Color(0xff59f2cc);
  static const aqua = Color(0xff62c9f6);
  static const iris = Color(0xffc19bff);
  static const rose = Color(0xffff82bd);
}

class DeckAtmosphere extends StatelessWidget {
  const DeckAtmosphere({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xff080d1c),
                  Color(0xff121a31),
                  Color(0xff0b1120),
                ],
                stops: [0, .58, 1],
              ),
            ),
          ),
        ),
        const Positioned(
          top: -280,
          right: -170,
          child: _AtmosphericGlow(size: 660, color: Color(0xff653674)),
        ),
        const Positioned(
          bottom: -250,
          left: -270,
          child: _AtmosphericGlow(size: 650, color: Color(0xff165d67)),
        ),
        const Positioned(
          top: 155,
          left: 185,
          child: _AtmosphericGlow(size: 320, color: Color(0xff3a305d)),
        ),
        Positioned.fill(child: child),
      ],
    ),
  );
}

class _AtmosphericGlow extends StatelessWidget {
  const _AtmosphericGlow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: .43),
            color.withValues(alpha: .14),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .42, 1],
        ),
      ),
    ),
  );
}

class DeckSurface extends StatelessWidget {
  const DeckSurface({
    super.key,
    required this.child,
    required this.top,
    required this.bottom,
    this.accent = DeckColor.line,
    this.padding = const EdgeInsets.all(22),
    this.radius = 23,
  });
  final Widget child;
  final Color top;
  final Color bottom;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [top, bottom],
      ),
      border: Border.all(color: accent.withValues(alpha: .52)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .24),
          blurRadius: 25,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: accent.withValues(alpha: .11),
          blurRadius: 25,
          spreadRadius: -13,
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius - 1),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class DeckOverline extends StatelessWidget {
  const DeckOverline(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
      color: color,
    ),
  );
}

class DeckAction extends StatelessWidget {
  const DeckAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.tone = DeckColor.aqua,
    this.primary = false,
    this.compact = false,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color tone;
  final bool primary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    final radius = BorderRadius.circular(compact ? 11 : 13);
    final foreground = !active
        ? DeckColor.subtle
        : primary
        ? DeckColor.voidInk
        : DeckColor.text;
    return Semantics(
      button: true,
      enabled: active,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: primary && active
                  ? [tone, Color.lerp(tone, Colors.white, .23)!]
                  : [const Color(0xff27304a), const Color(0xff1b2438)],
            ),
            border: Border.all(
              color: active
                  ? tone.withValues(alpha: primary ? .80 : .45)
                  : DeckColor.line.withValues(alpha: .6),
            ),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 15,
                vertical: compact ? 10 : 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: compact ? 16 : 18, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DeckField extends StatelessWidget {
  const DeckField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.fieldKey,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hint;
  final Key? fieldKey;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    onChanged: onChanged,
    maxLines: maxLines,
    style: const TextStyle(color: DeckColor.text, fontSize: 13.5),
    cursorColor: DeckColor.mint,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: DeckColor.subtle),
      filled: true,
      fillColor: const Color(0xff10182b),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DeckColor.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: DeckColor.line.withValues(alpha: .9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DeckColor.mint, width: 1.5),
      ),
    ),
  );
}

class DeckSelect<T> extends StatelessWidget {
  const DeckSelect({
    super.key,
    required this.name,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String name;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xff10182b),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: DeckColor.line),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        key: ValueKey('deck-$name:$value'),
        value: value,
        isExpanded: true,
        isDense: true,
        dropdownColor: const Color(0xff1a2540),
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: DeckColor.muted,
          size: 20,
        ),
        style: const TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: DeckColor.text,
        ),
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}

class DeckInfo extends StatelessWidget {
  const DeckInfo(this.label, {super.key, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: color.withValues(alpha: .35)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class DeckBeacon extends StatefulWidget {
  const DeckBeacon({super.key, required this.color});
  final Color color;
  @override
  State<DeckBeacon> createState() => _DeckBeaconState();
}

class _DeckBeaconState extends State<DeckBeacon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final amount = reduced ? .4 : _pulse.value;
        return SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: Container(
              width: 10 + amount * 6,
              height: 10 + amount * 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: .36 + .18 * amount),
                    blurRadius: 9 + amount * 9,
                    spreadRadius: amount * 3,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
