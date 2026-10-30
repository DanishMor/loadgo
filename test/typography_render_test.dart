import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';

/// E8: every language renders with the real bundled fonts (Mukta, then the
/// Noto chain) in every look, at 2.0x text, in its own direction. The glyph
/// coverage itself is proven from the font files by typography_test.dart.
Future<void> _loadFonts() async {
  final families = <String, List<String>>{
    'Mukta': ['assets/fonts/mukta/Mukta-Regular.ttf', 'assets/fonts/mukta/Mukta-Bold.ttf'],
    'NotoSans': ['assets/fonts/NotoSans-Regular.ttf'],
    'NotoSansKannada': ['assets/fonts/NotoSansKannada-Regular.ttf'],
    'NotoSansTamil': ['assets/fonts/NotoSansTamil-Regular.ttf'],
    'NotoSansTelugu': ['assets/fonts/NotoSansTelugu-Regular.ttf'],
    'NotoSansGujarati': ['assets/fonts/NotoSansGujarati-Regular.ttf'],
    'NotoSansBengali': ['assets/fonts/NotoSansBengali-Regular.ttf'],
    'NotoSansGurmukhi': ['assets/fonts/NotoSansGurmukhi-Regular.ttf'],
    'NotoNaskhArabic': ['assets/fonts/NotoNaskhArabic-Regular.ttf'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final path in e.value) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// A few real strings of [lang]: the language name, the appearance texts and a price.
List<String> _samples(AppLanguage lang) => [
      for (final k in ['themeMode', 'themeLook', 'themeLookSignature', 'themeMidnight', 'a11ySend'])
        ?T.data[k]?[lang],
      '₹ 1,23,456.50',
    ];

void main() {
  setUpAll(_loadFonts);

  test('price styles use equal-width digits on the type scale', () {
    for (final s in [DsType.number, DsType.price, DsType.numberSmall]) {
      expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(s.fontFamily, DsType.family);
      expect(s.fontFamilyFallback, DsType.fallback);
    }
    expect(DsType.price.fontSize, DsType.headline.fontSize);
    expect(DsType.numberSmall.fontSize, greaterThanOrEqualTo(12));
  });

  test('tabular digits really have equal widths in Mukta', () {
    double width(String s) {
      final p = TextPainter(text: TextSpan(text: s, style: DsType.number), textDirection: TextDirection.ltr)..layout();
      return p.width;
    }
    expect(width('1111'), closeTo(width('8888'), 0.5));
  });

  for (final lang in AppLanguage.values) {
    testWidgets('${lang.name} renders in every look at 2.0x without overflow', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      for (final style in ThemeStyle.values) {
        for (final b in Brightness.values) {
          await t.pumpWidget(MaterialApp(
            themeAnimationDuration: Duration.zero,
            theme: AppTheme.build(b, style: style),
            builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
            home: Scaffold(
              body: Directionality(
                textDirection: lang.textDirection,
                child: ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
                  for (final s in _samples(lang)) Text(s, style: DsType.body),
                  Text(_samples(lang).first, style: DsType.headline),
                  Text('₹ 14,500', style: DsType.price),
                ]),
              ),
            ),
          ));
          expect(t.takeException(), isNull, reason: '${lang.name} $style $b');
        }
      }
      expect(_samples(lang).length, greaterThan(3), reason: 'samples missing for ${lang.name}');
    });
  }
}
