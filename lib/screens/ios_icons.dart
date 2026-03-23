import 'package:flutter/cupertino.dart';

/// Drop-in icon widgets that render with zero package dependencies.
/// Uses Unicode characters that map to SF Symbols on iOS and
/// fall back gracefully on Android.
class AppIcon extends StatelessWidget {
  final String glyph;
  final double size;
  final Color color;

  const AppIcon(this.glyph,
      {super.key,
        this.size = 20,
        this.color = const Color(0xFF8E8E93)});

  @override
  Widget build(BuildContext context) {
    return Text(
      glyph,
      style: TextStyle(
        fontSize: size,
        color: color,
        height: 1,
        fontFamily: '.SF Pro Display',
        decoration: TextDecoration.none,
      ),
    );
  }
}

// ── Glyph constants ──────────────────────────────────────────────
class Ic {
  Ic._();
  static const home        = '⌂';
  static const history     = '◷';
  static const run         = '▶';
  static const stop        = '■';
  static const pause       = '⏸';
  static const play        = '▶';
  static const camera      = '⊙';
  static const person      = '◉';
  static const map         = '⊞';
  static const fire        = '◈';
  static const bolt        = '⚡';
  static const boltOff     = '⊘';
  static const star        = '★';
  static const clock       = '◔';
  static const timer       = '⏱';
  static const steps       = '◎';
  static const pace        = '◐';
  static const distance    = '→';
  static const cal         = '◆';
  static const gps         = '⊕';
  static const flip        = '↻';
  static const back        = '‹';
  static const close       = '×';
  static const collapse    = '⊠';
  static const detail      = '↗';
  static const trash       = '⊟';
  static const repeat      = '↺';
  static const week        = '▦';
  static const longest     = '⇥';
  static const speed       = '◑';
  static const photo       = '⊙';
  static const cadence     = '⊛';
}

/// A circular icon container — standard iOS tappable icon style
class IconChip extends StatelessWidget {
  final String glyph;
  final double size;
  final Color bg;
  final Color fg;
  final double containerSize;

  const IconChip(
      this.glyph, {
        super.key,
        this.size = 16,
        this.bg = const Color(0xFF2C2C2E),
        this.fg = const Color(0xFF8E8E93),
        this.containerSize = 36,
      });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: containerSize,
      height: containerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: const Color(0xFF3A3A3C), width: 0.5),
      ),
      child: Center(
        child: AppIcon(glyph, size: size, color: fg),
      ),
    );
  }
}