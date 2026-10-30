import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/pricing/price_transparency.dart';
import 'package:transport_app/core/pricing/route_rates.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/widgets/price_transparency_sheet.dart';

/// E27: the price card and the no-hidden-fee guard.
void main() {
  group('guard: no hidden fee', () {
    test('every money field of the fare is a listed charge (a new fee must get a line)', () {
      final keys = PricingService.quote(vehicleType: '14ft', distanceKm: 120).toMap().keys.toSet();
      final surged = FareBreakdown.fromMap({...PricingService.quote(vehicleType: '14ft', distanceKm: 120).toMap(), 'surgeCharge': 500, 'surgePercent': 10, 'surgeKind': 'peak'}).toMap().keys;
      final all = {...keys, ...surged};
      expect(all.difference({...PriceTransparency.chargeKeys, ...PriceTransparency.notCharges}), isEmpty, reason: 'unlisted field in FareBreakdown.toMap');
      expect(PriceTransparency.chargeKeys.toSet().difference(all), isEmpty, reason: 'a listed charge no longer exists');
    });

    test('the fare breakdown view shows every charge', () {
      final view = File('lib/core/widgets/fare_breakdown.dart').readAsStringSync();
      for (final k in PriceTransparency.chargeKeys) {
        expect(view, contains('f.$k'), reason: '$k is not shown by FareBreakdownView');
      }
    });

    test('the lines add up to the total for many quotes, rentals and extras', () {
      for (final type in ['Tempo', '14ft', '20ft', '32ft']) {
        for (final km in [1, 7, 45, 300, 1400]) {
          for (final extras in [(0, 0, 0), (2, 45, 1)]) {
            final f = PricingService.quote(vehicleType: type, distanceKm: km, extraStops: extras.$1, waitingMinutes: extras.$2, helpers: extras.$3);
            expect(PriceTransparency.addsUp(f), isTrue, reason: '$type $km km $extras');
            expect(PriceTransparency.lines(f).every((l) => l.$2 > 0), isTrue);
          }
        }
        final r = PricingService.quoteRental(vehicleType: type, hours: 8);
        expect(PriceTransparency.addsUp(r), isTrue, reason: 'rental $type');
      }
    });
  });

  test('fair position against the usual range', () {
    const r = RateRange(100000, 120000, 140000, 9);
    expect(fairPosition(90000, r), FairPosition.below);
    expect(fairPosition(120000, r), FairPosition.usual);
    expect(fairPosition(150000, r), FairPosition.above);
    expect(fairPosition(120000, null), FairPosition.unknown);
    expect(fairPosition(120000, const RateRange(0, 0, 0, 0)), FairPosition.unknown);
  });

  Widget host(Widget child, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
        notifier: ValueNotifier(lang),
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: lang.textDirection, child: w!)),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  testWidgets('the sheet: lines, promise, own price and position', (t) async {
    final f = PricingService.quote(vehicleType: '14ft', distanceKm: 120);
    await t.pumpWidget(host(PriceTransparencySheet(fare: f, range: RateRange(f.total - 50000, f.total, f.total + 50000, 12), yourPricePaise: f.total + 100000)));
    expect(find.byKey(const ValueKey('ptPromise')), findsOneWidget);
    expect(find.byKey(const ValueKey('pxYourPrice')), findsOneWidget);
    expect(find.byKey(const ValueKey('pxPos_above')), findsOneWidget);
    await t.pumpWidget(host(PriceTransparencySheet(fare: f)));
    expect(find.byKey(const ValueKey('pxYourPrice')), findsNothing);
    expect(find.byKey(const ValueKey('pxPos_unknown')), findsNothing);
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
      t.view.physicalSize = const Size(320, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final f = PricingService.quote(vehicleType: '20ft', distanceKm: 400, extraStops: 2, helpers: 1);
      await t.pumpWidget(host(PriceTransparencySheet(fare: f, range: RateRange(f.total, f.total, f.total, 7), yourPricePaise: f.total), lang: lang, b: b, scale: 2));
      expect(t.takeException(), isNull);
    });
  }
}
