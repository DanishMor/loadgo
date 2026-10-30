import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pricing/price_transparency.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/share/quote_share_sheet.dart';
import 'package:transport_app/core/share/quote_summary.dart';
import 'package:transport_app/core/theme/app_theme.dart';

/// E31: share a quote as a picture, a PDF or text (flag quoteShare).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'c1');
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });

  const labels = {'route': 'Route', 'goods': 'Goods', 'vehicle': 'Vehicle', 'when': 'When', 'total': 'Total', 'ref': 'Reference', 'note': 'An estimate.'};
  final fare = PricingService.quote(vehicleType: '14ft', distanceKm: 150);
  QuoteSummary summary({String ref = ''}) => QuoteSummary(
    title: 'Truck quote',
    pickup: 'Pune',
    drop: 'Surat',
    goods: 'Cotton',
    weightTons: 3,
    vehicle: '14 ft',
    lines: QuoteSummary.linesOf(fare, (k) => k),
    pricePaise: fare.total,
    reference: ref,
  );

  test('text: route, goods, every line and the total; a short reference; nothing personal', () {
    final t = summary(ref: QuoteSummary.refOf('abcDEF123xyz')).asText(labels);
    expect(t, contains('Route: Pune → Surat'));
    expect(t, contains('Goods: Cotton, 3 T'));
    for (final (k, _) in PriceTransparency.lines(fare)) {
      expect(t, contains('$k: '), reason: k);
    }
    expect(t, contains('Reference: 123XYZ'));
    expect(RegExp(r'\+?91\d{10}|\b\d{6}\b').hasMatch(t.replaceAll('123XYZ', '')), isFalse, reason: 'no phone number or code');
    expect(QuoteSummary.refOf('ab'), 'AB');
  });

  testWidgets('PDF: builds with the app fonts (Indian scripts) and is a PDF', (t) async {
    final bytes = (await t.runAsync(() => summary().toPdf({...labels, 'route': 'रास्ता'})))!;
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  Widget host(Widget child, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
    notifier: ValueNotifier(lang),
    child: MaterialApp(
      theme: AppTheme.build(b, style: ThemeStyle.signature),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: lang.textDirection, child: w!),
      ),
      home: Scaffold(body: child),
    ),
  );

  testWidgets('sheet: picture, PDF and text each hand over the right thing', (t) async {
    final got = <(QuoteShareKind, int, String)>[];
    await t.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showQuoteShare(context, summary(), onShare: (k, bytes, text) async => got.add((k, (bytes ?? Uint8List(0)).length, text))),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('qsCard')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('qsText')));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('qsPdf')));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await t.pumpAndSettle();
    expect(got.map((g) => g.$1), [QuoteShareKind.text, QuoteShareKind.pdf]);
    expect(got.first.$2, 0);
    expect(got[1].$2, greaterThan(1000));
    expect(got.first.$3, contains('Pune → Surat'));
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
      t.view.physicalSize = const Size(320, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showQuoteShare(context, summary(ref: 'XYZ123')),
              child: const Text('open'),
            ),
          ),
          lang: lang,
          b: b,
          scale: 2,
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
