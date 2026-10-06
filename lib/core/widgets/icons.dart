import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/astro/moon_phase.dart';

/// A fish silhouette, drawn rather than taken from an icon font so it is identical on iOS,
/// Android and web (Material Icons has no fish).
class FishIcon extends StatelessWidget {
  const FishIcon({super.key, this.size = 24, this.color, this.semanticLabel});

  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: semanticLabel == null,
      child: SizedBox(width: size, height: size, child: CustomPaint(painter: _FishPainter(c))),
    );
  }
}

class _FishPainter extends CustomPainter {
  const _FishPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()..color = color;

    // Body: a pointed-nose teardrop swimming left.
    final body = Path()
      ..moveTo(w * 0.04, h * 0.50)
      ..quadraticBezierTo(w * 0.28, h * 0.18, w * 0.62, h * 0.30)
      ..quadraticBezierTo(w * 0.80, h * 0.38, w * 0.80, h * 0.50)
      ..quadraticBezierTo(w * 0.80, h * 0.62, w * 0.62, h * 0.70)
      ..quadraticBezierTo(w * 0.28, h * 0.82, w * 0.04, h * 0.50)
      ..close();

    final tail = Path()
      ..moveTo(w * 0.72, h * 0.50)
      ..lineTo(w * 0.97, h * 0.24)
      ..quadraticBezierTo(w * 0.88, h * 0.50, w * 0.97, h * 0.76)
      ..close();

    final fin = Path()
      ..moveTo(w * 0.40, h * 0.28)
      ..lineTo(w * 0.52, h * 0.10)
      ..lineTo(w * 0.60, h * 0.31)
      ..close();

    var silhouette = Path.combine(PathOperation.union, body, tail);
    silhouette = Path.combine(PathOperation.union, silhouette, fin);

    // Cut the eye out so the icon works on any background.
    final eye = Path()..addOval(Rect.fromCircle(center: Offset(w * 0.24, h * 0.46), radius: w * 0.04));
    canvas.drawPath(Path.combine(PathOperation.difference, silhouette, eye), paint);
  }

  @override
  bool shouldRepaint(_FishPainter old) => old.color != color;
}

/// The moon at a given phase: a dim disc with the lit part drawn over it.
class MoonIcon extends StatelessWidget {
  const MoonIcon({super.key, required this.cycleFraction, this.size = 40, this.lit, this.dim});

  /// Convenience for a date.
  MoonIcon.forDate(DateTime date, {super.key, this.size = 40, this.lit, this.dim})
      : cycleFraction = MoonPhase.cycleFraction(date);

  /// 0...1 through the synodic month: 0 = new moon, 0.5 = full.
  final double cycleFraction;
  final double size;
  final Color? lit;
  final Color? dim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: MoonPainter(
            cycleFraction: cycleFraction,
            lit: lit ?? scheme.tertiary,
            dim: dim ?? scheme.onSurface.withValues(alpha: 0.14),
          ),
        ),
      ),
    );
  }
}

class MoonPainter extends CustomPainter {
  const MoonPainter({required this.cycleFraction, required this.lit, required this.dim});

  final double cycleFraction;
  final Color lit;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, r, Paint()..color = dim);

    final cosv = math.cos(2 * math.pi * cycleFraction); // 1 at new, -1 at full
    final waxing = cycleFraction < 0.5;
    final disc = Rect.fromCircle(center: c, radius: r);
    final terminator = Rect.fromCenter(center: c, width: 2 * cosv.abs() * r, height: 2 * r);

    final path = Path();
    if (waxing) {
      // Lit limb on the right (northern hemisphere): top → right → bottom, then back up the
      // terminator — bulging right for a crescent, left for a gibbous.
      path.arcTo(disc, -math.pi / 2, math.pi, true);
      path.arcTo(terminator, math.pi / 2, cosv > 0 ? -math.pi : math.pi, false);
    } else {
      path.arcTo(disc, math.pi / 2, math.pi, true);
      path.arcTo(terminator, -math.pi / 2, cosv > 0 ? -math.pi : math.pi, false);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = lit);
  }

  @override
  bool shouldRepaint(MoonPainter old) =>
      old.cycleFraction != cycleFraction || old.lit != lit || old.dim != dim;
}
