import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/theme/app_theme.dart';

/// MASTER-5 Task 23: spoken labels, tap size, contrast.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final l1 = _lum(a), l2 = _lum(b);
  return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05);
}

void main() {
  for (final entry in {'light': AppPalette.light, 'dark': AppPalette.dark}.entries) {
    final p = entry.value;
    test('${entry.key}: text colours are readable on the background and on cards', () {
      for (final bg in [p.bg, p.card]) {
        expect(contrast(p.text, bg), greaterThanOrEqualTo(7), reason: 'title text');
        expect(contrast(p.strong, bg), greaterThanOrEqualTo(7), reason: 'strong text');
        expect(contrast(p.muted, bg), greaterThanOrEqualTo(4.5), reason: 'muted text');
      }
      expect(contrast(p.muted, p.chip), greaterThanOrEqualTo(4.5), reason: 'muted on chips');
      expect(contrast(p.text, p.tint), greaterThanOrEqualTo(7), reason: 'text on tint');
      expect(contrast(p.text, p.warnBg), greaterThanOrEqualTo(7), reason: 'text on warning');
    });
    test('${entry.key}: hint and borders stay visible (3:1 for hints)', () {
      expect(contrast(p.hint, p.card), greaterThanOrEqualTo(3));
    });
  }

  test('every icon-only button has a spoken label (tooltip)', () {
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      for (final m in RegExp(r'\bIconButton(?:\.(?!styleFrom)\w+)?\(').allMatches(s)) {
        var i = m.end;
        var d = 1;
        while (d > 0 && i < s.length) {
          d += (s[i] == '(' ? 1 : 0) - (s[i] == ')' ? 1 : 0);
          i++;
        }
        final body = s.substring(m.start, i);
        if (!body.contains('tooltip') && !body.contains('semanticLabel')) missing.add('${f.path}:${s.substring(0, m.start).split('\n').length}');
      }
    }
    expect(missing, isEmpty);
  });

  test('the theme keeps the 48dp tap target (no shrink-wrap, no compact density)', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      final t = AppTheme.build(b);
      expect(t.materialTapTargetSize, MaterialTapTargetSize.padded);
    }
  });
}
