import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/theme/design_tokens.dart';

/// L4: the contrast of every colour pair the design system uses, in light and
/// dark (WCAG 2.x): text 4.5:1 or more, UI parts 3:1 or more.
double _lin(int v) {
  final s = v / 255;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _lum(Color c) => 0.2126 * _lin((c.r * 255).round()) + 0.7152 * _lin((c.g * 255).round()) + 0.0722 * _lin((c.b * 255).round());

double ratio(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  final hi = math.max(x, y), lo = math.min(x, y);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final sets = {'light': DsColors.light, 'dark': DsColors.dark, 'signature': DsColors.signature, 'midnight': DsColors.midnight};

  for (final e in sets.entries) {
    final c = e.value;
    final name = e.key;

    test('$name: text pairs are 4.5:1 or more', () {
      final pairs = <String, (Color, Color)>{
        'text on bg': (c.text, c.bg),
        'text on surface': (c.text, c.surface),
        'textStrong on surface': (c.textStrong, c.surface),
        'textMuted on bg': (c.textMuted, c.bg),
        'textMuted on surface': (c.textMuted, c.surface),
        'textMuted on chip': (c.textMuted, c.chip),
        'textHint on bg': (c.textHint, c.bg),
        'textHint on surface': (c.textHint, c.surface),
        'onPrimary on primary': (c.onPrimary, c.primary),
        'onAccent on accent': (c.onAccent, c.accent),
        'primary on surface (links)': (c.primary, c.surface),
        'primary on tint': (c.primary, c.tint),
        'text on tint': (c.text, c.tint),
        'success on successBg': (c.success, c.successBg),
        'success on surface': (c.success, c.surface),
        'warning on warningBg': (c.warning, c.warningBg),
        'warning on surface': (c.warning, c.surface),
        'error on errorBg': (c.error, c.errorBg),
        'error on surface': (c.error, c.surface),
        'onAdminBanner on adminBanner': (c.onAdminBanner, c.adminBanner),
      };
      final low = {for (final p in pairs.entries) p.key: ratio(p.value.$1, p.value.$2)}..removeWhere((_, r) => r >= 4.5);
      expect(low, isEmpty, reason: 'below 4.5:1 in $name');
    });

    test('$name: UI parts are 3:1 or more', () {
      final pairs = <String, (Color, Color)>{
        'inputBorder on surface': (c.inputBorder, c.surface),
        'inputBorder on bg': (c.inputBorder, c.bg),
        'focus on surface': (c.focus, c.surface),
        'focus on bg': (c.focus, c.bg),
        'primary on bg': (c.primary, c.bg),
        'accentStrong on surface': (c.accentStrong, c.surface),
        'accentStrong on bg': (c.accentStrong, c.bg),
        'roleCustomer on surface': (c.roleCustomer, c.surface),
        'roleDriver on surface': (c.roleDriver, c.surface),
        'roleTransporter on surface': (c.roleTransporter, c.surface),
        'roleCustomer on bg': (c.roleCustomer, c.bg),
        'roleDriver on bg': (c.roleDriver, c.bg),
        'roleTransporter on bg': (c.roleTransporter, c.bg),
        'success on bg': (c.success, c.bg),
        'warning on bg': (c.warning, c.bg),
        'error on bg': (c.error, c.bg),
      };
      final low = {for (final p in pairs.entries) p.key: ratio(p.value.$1, p.value.$2)}..removeWhere((_, r) => r >= 3.0);
      expect(low, isEmpty, reason: 'below 3:1 in $name');
    });
  }

  test('dark mode is navy-tinted, not pure black', () {
    for (final c in [DsColors.dark.bg, DsColors.dark.surface]) {
      expect(c.toARGB32() & 0xFFFFFF, isNot(0x000000));
      expect((c.b * 255).round(), greaterThan((c.r * 255).round()), reason: 'blue leads the dark surfaces');
    }
  });

  test('every colour is opaque (no hidden alpha lowering contrast)', () {
    for (final c in sets.values) {
      for (final v in [c.bg, c.surface, c.chip, c.tint, c.text, c.textStrong, c.textMuted, c.textHint, c.border, c.inputBorder, c.focus, c.primary, c.onPrimary, c.accent, c.onAccent, c.accentStrong, c.success, c.successBg, c.warning, c.warningBg, c.error, c.errorBg, c.roleCustomer, c.roleDriver, c.roleTransporter, c.adminBanner, c.onAdminBanner]) {
        expect((v.a * 255).round(), 255);
      }
    }
  });

  test('E6 brand palette: Navy, Ink, Gold on Ivory meet WCAG AA', () {
    final text = <String, (Color, Color)>{
      'ink on ivory': (DsLuxe.ink, DsLuxe.ivory),
      'navy on ivory': (DsLuxe.navy, DsLuxe.ivory),
      'ivory on navy': (DsLuxe.ivory, DsLuxe.navy),
      'ivory on ink': (DsLuxe.ivory, DsLuxe.ink),
      'ink on gold': (DsLuxe.ink, DsLuxe.gold),
      'goldDeep on ivory': (DsLuxe.goldDeep, DsLuxe.ivory),
      'gold on ink': (DsLuxe.gold, DsLuxe.ink),
      'gold on navy': (DsLuxe.gold, DsLuxe.navy),
      'goldLight on black': (DsLuxe.goldLight, const Color(0xFF000000)),
    };
    final low = {for (final p in text.entries) p.key: ratio(p.value.$1, p.value.$2)}..removeWhere((_, r) => r >= 4.5);
    expect(low, isEmpty, reason: 'brand pairs below 4.5:1');
    // Gold on Ivory is decoration only (hairlines, the logo dot), never text.
    expect(ratio(DsLuxe.gold, DsLuxe.ivory), lessThan(4.5));
  });

  test('Midnight is true black; Signature sits on Ivory', () {
    expect(DsColors.midnight.bg.toARGB32(), 0xFF000000);
    expect(DsColors.signature.bg, DsLuxe.ivory);
    expect(DsColors.signature.accent, DsLuxe.gold);
  });

  test('spacing is on the 4/8 grid and the radius, elevation and motion scales rise', () {
    final space = [DsSpace.s1, DsSpace.s2, DsSpace.s3, DsSpace.s4, DsSpace.s5, DsSpace.s6, DsSpace.s8, DsSpace.s10, DsSpace.s12];
    for (final s in space) {
      expect(s % 4, 0, reason: '$s');
    }
    expect([...space]..sort(), space);
    expect(DsSpace.tapMin, greaterThanOrEqualTo(48));
    expect(DsSpace.tapBig, greaterThan(DsSpace.tapMin));
    expect([DsRadius.sm, DsRadius.md, DsRadius.lg, DsRadius.xl, DsRadius.pill], [8, 12, 16, 24, 999]);
    expect([DsElevation.none, DsElevation.low, DsElevation.card, DsElevation.sheet, DsElevation.dialog], [0, 1, 2, 4, 8]);
    expect(DsMotion.fast < DsMotion.normal && DsMotion.normal < DsMotion.slow, isTrue);
  });

  test('type scale: body is 16 sp, nothing below 12 sp, sizes rise', () {
    final sizes = [DsType.caption, DsType.bodySmall, DsType.body, DsType.title, DsType.headline, DsType.display].map((s) => s.fontSize!).toList();
    expect(sizes.first, greaterThanOrEqualTo(12));
    expect(DsType.body.fontSize, 16);
    for (var i = 1; i < sizes.length; i++) {
      expect(sizes[i], greaterThanOrEqualTo(sizes[i - 1]));
    }
    expect(DsType.number.fontFeatures, isNotEmpty);
    final t = DsType.textTheme(DsColors.light);
    expect(t.bodyLarge!.color, DsColors.light.text);
    expect(t.bodySmall!.color, DsColors.light.textMuted);
  });

  testWidgets('motion drops to zero when the system or Low-end mode asks for it', (tester) async {
    late BuildContext ctx;
    Future<void> pump(bool disable) => tester.pumpWidget(MediaQuery(
          data: MediaQueryData(disableAnimations: disable),
          child: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
        ));
    await pump(false);
    expect(DsMotion.duration(ctx, DsMotion.normal), DsMotion.normal);
    await pump(true);
    expect(DsMotion.duration(ctx, DsMotion.normal), Duration.zero);
    await pump(false);
    DsMotion.lowEnd = true;
    addTearDown(() => DsMotion.lowEnd = false);
    expect(DsMotion.duration(ctx, DsMotion.slow), Duration.zero);
  });
}
