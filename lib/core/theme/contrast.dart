import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// WCAG 2.x contrast helpers. Pure Dart, used by the design system to keep a
/// colour readable on a background (for example an old screen that still passes
/// its own colour to a badge) and by the tests.
double _lin(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double relativeLuminance(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

/// Contrast ratio between two colours, 1 (same) to 21 (black on white).
double contrastRatio(Color a, Color b) {
  final x = relativeLuminance(a), y = relativeLuminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// [fg] itself when it reads on [bg] at [min]:1, otherwise [fg] moved towards
/// black (on a light [bg]) or white (on a dark [bg]) in small steps until it
/// does. Keeps the hue as far as it can; always returns an opaque colour.
Color ensureContrast(Color fg, Color bg, {double min = 4.5}) {
  final opaque = fg.withValues(alpha: 1);
  if (contrastRatio(opaque, bg) >= min) return opaque;
  final toward = relativeLuminance(bg) > 0.4 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  for (var i = 1; i <= 20; i++) {
    final c = Color.lerp(opaque, toward, i / 20)!;
    if (contrastRatio(c, bg) >= min) return c;
  }
  return toward;
}
