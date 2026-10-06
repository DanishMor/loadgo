import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/surge_strings.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/pricing/pricing_config.dart';
import 'package:transport_app/core/pricing/surge.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/widgets/fare_breakdown.dart';

const rule = PricingRule(baseFare: 50000, perKm: 2800, minimumFare: 80000);

SurgeRule enabled({List<FestivalRange> festivals = const [], int cap = 30}) => SurgeRule(enabled: true, festivals: festivals, capPercent: cap);

void main() {
  setUp(() => languageNotifier.value = AppLanguage.english);

  group('SurgeCalculator', () {
    test('default is OFF at every hour', () {
      for (var h = 0; h < 24; h++) {
        expect(SurgeCalculator.percentAt(DateTime(2026, 10, 6, h), SurgeRule.off), 0);
      }
      expect(SurgeRule.fromMap(null).enabled, isFalse);
      expect(SurgeRule.fromMap({'peak': {'percent': 50}}).enabled, isFalse);
    });

    test('peak window boundaries: start inclusive, end exclusive', () {
      final r = enabled();
      expect(SurgeCalculator.percentAt(DateTime(2026, 10, 6, 7, 59), r), 0);
      expect(SurgeCalculator.percentAt(DateTime(2026, 10, 6, 8), r), 10);
      expect(SurgeCalculator.percentAt(DateTime(2026, 10, 6, 10, 59), r), 10);
      expect(SurgeCalculator.percentAt(DateTime(2026, 10, 6, 11), r), 0);
      expect(SurgeCalculator.at(DateTime(2026, 10, 6, 9), r).kind, SurgeKind.peak);
    });

    test('night window wraps past midnight', () {
      final r = enabled();
      for (final h in [22, 23, 0, 3, 4]) {
        final q = SurgeCalculator.at(DateTime(2026, 10, 6, h), r);
        expect((q.percent, q.kind), (15, SurgeKind.night), reason: '$h');
      }
      expect(SurgeCalculator.percentAt(DateTime(2026, 10, 6, 5), r), 0);
      expect(SurgeCalculator.percentAt(DateTime(2026, 10, 6, 21, 59), r), 0);
    });

    test('festival ranges cover whole days, inclusive', () {
      final f = FestivalRange(from: DateTime(2026, 11, 8), to: DateTime(2026, 11, 10), percent: 20, name: 'Diwali');
      final r = enabled(festivals: [f]);
      expect(SurgeCalculator.percentAt(DateTime(2026, 11, 7, 14), r), 0);
      expect(SurgeCalculator.at(DateTime(2026, 11, 8, 0, 1), r).kind, SurgeKind.festival);
      expect(SurgeCalculator.percentAt(DateTime(2026, 11, 10, 21, 59), r), 20);
      expect(SurgeCalculator.percentAt(DateTime(2026, 11, 11, 12), r), 0);
    });

    test('active windows add up and the cap applies', () {
      final f = FestivalRange(from: DateTime(2026, 11, 8), to: DateTime(2026, 11, 8), percent: 20);
      // 23:00 on a festival day: night 15 + festival 20 = 35, capped at 30.
      final r = enabled(festivals: [f]);
      final q = SurgeCalculator.at(DateTime(2026, 11, 8, 23), r);
      expect(q.percent, 30);
      expect(q.kind, SurgeKind.festival);
      expect(SurgeCalculator.percentAt(DateTime(2026, 11, 8, 23), enabled(festivals: [f], cap: 100)), 35);
      expect(SurgeCalculator.percentAt(DateTime(2026, 11, 8, 23), enabled(festivals: [f], cap: 0)), 0);
    });

    test('equal start and end hours switch a window off', () {
      const r = SurgeRule(enabled: true, peak: SurgeWindow(startHour: 8, endHour: 8, percent: 10), night: SurgeWindow(startHour: 1, endHour: 1, percent: 10));
      for (var h = 0; h < 24; h++) {
        expect(SurgeCalculator.percentAt(DateTime(2026, 10, 6, h), r), 0);
      }
    });

    test('parsing ignores bad festival rows and keeps defaults for bad numbers', () {
      final r = SurgeRule.fromMap({
        'enabled': true,
        'capPercent': -3,
        'peak': {'startHour': 99, 'endHour': 'x', 'percent': 12},
        'festivals': [
          {'from': '2026-11-08', 'to': '2026-11-07', 'percent': 10},
          {'from': 'nope', 'to': '2026-11-07', 'percent': 10},
          {'from': '2026-11-08', 'to': '2026-11-09', 'percent': 0},
          {'from': '2026-11-08', 'to': '2026-11-09', 'percent': 18, 'name': 'Diwali'},
          'junk',
        ],
      });
      expect(r.enabled, isTrue);
      expect(r.capPercent, 30);
      expect((r.peak.startHour, r.peak.endHour, r.peak.percent), (8, 11, 12));
      expect(r.festivals.length, 1);
      expect(r.festivals.single.name, 'Diwali');
    });

    test('toMap round-trips through fromMap', () {
      final r = enabled(festivals: [FestivalRange(from: DateTime(2026, 11, 8), to: DateTime(2026, 11, 9), percent: 18, name: 'D')], cap: 25);
      final back = SurgeRule.fromMap(r.toMap());
      expect(back.toMap(), r.toMap());
      expect(PricingConfig.fromMap(PricingConfig(categories: defaultPricing.categories, surge: r).toMap()).surge.toMap(), r.toMap());
    });
  });

  group('fare with surge', () {
    test('no surge: nothing changes and the map has no surge keys', () {
      final f = FareCalculator.calculate(rule: rule, distanceKm: 100, platformFeePercent: 5, gstPercent: 5);
      expect(f.surgeCharge, 0);
      expect(f.toMap().containsKey('surgeCharge'), isFalse);
    });

    test('surge is a percent of base + distance, in paise, and joins the trip fare', () {
      final plain = FareCalculator.calculate(rule: rule, distanceKm: 100, platformFeePercent: 5, gstPercent: 5);
      final f = FareCalculator.calculate(rule: rule, distanceKm: 100, platformFeePercent: 5, gstPercent: 5, surge: const SurgeQuote(10, SurgeKind.peak));
      // (50000 + 280000) * 10% = 33000
      expect(f.surgeCharge, 33000);
      expect((f.surgePercent, f.surgeKind), (10, SurgeKind.peak));
      expect(f.tripFare, plain.tripFare + 33000);
      expect(f.platformFee, (f.tripFare * 0.05).round());
      expect(f.total, f.tripFare + f.platformFee + f.gst);
    });

    test('rounds half up and applies to the minimum-fare top-up too', () {
      // 1 km: 50000 + 2800 = 52800 < 80000, top-up makes the freight 80000.
      final f = FareCalculator.calculate(rule: rule, distanceKm: 1, surge: const SurgeQuote(15, SurgeKind.night));
      expect(f.surgeCharge, 12000);
      const odd = PricingRule(baseFare: 1001, perKm: 0, minimumFare: 0);
      expect(FareCalculator.calculate(rule: odd, distanceKm: 0, surge: const SurgeQuote(10, SurgeKind.peak)).surgeCharge, 100); // 100.1
      const half = PricingRule(baseFare: 1005, perKm: 0, minimumFare: 0);
      expect(FareCalculator.calculate(rule: half, distanceKm: 0, surge: const SurgeQuote(10, SurgeKind.peak)).surgeCharge, 101); // 100.5 up
    });

    test('estimate map round-trips with the surge lines', () {
      final f = FareCalculator.calculate(rule: rule, distanceKm: 100, surge: const SurgeQuote(20, SurgeKind.festival));
      final back = FareBreakdown.fromMap(Map<String, dynamic>.from(f.toMap()));
      expect((back.surgeCharge, back.surgePercent, back.surgeKind), (f.surgeCharge, 20, SurgeKind.festival));
      expect(back.total, f.total);
    });

    test('PricingService.quote looks the surge up at the pickup time', () {
      PricingService.notifier.value = PricingConfig(categories: defaultPricing.categories, surge: enabled());
      addTearDown(PricingService.reset);
      final peak = PricingService.quote(vehicleType: 'Mini', distanceKm: 100, at: DateTime(2026, 10, 6, 9));
      final noon = PricingService.quote(vehicleType: 'Mini', distanceKm: 100, at: DateTime(2026, 10, 6, 13));
      final unknown = PricingService.quote(vehicleType: 'Mini', distanceKm: 100);
      expect(peak.surgeCharge, greaterThan(0));
      expect(noon.surgeCharge, 0);
      expect(unknown.surgeCharge, 0);
    });
  });

  group('breakdown widget', () {
    Widget app(FareBreakdown f) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: SingleChildScrollView(child: FareBreakdownView(fare: f)))));

    for (final (kind, text) in [(SurgeKind.peak, 'Peak hours (10%)'), (SurgeKind.night, 'Night charge (10%)'), (SurgeKind.festival, 'Festival demand (10%)')]) {
      testWidgets('shows the $kind label', (t) async {
        final f = FareCalculator.calculate(rule: rule, distanceKm: 100, surge: SurgeQuote(10, kind));
        await t.pumpWidget(app(f));
        expect(find.text(text), findsOneWidget);
      });
    }

    testWidgets('no surge line without surge', (t) async {
      await t.pumpWidget(app(FareCalculator.calculate(rule: rule, distanceKm: 100)));
      expect(find.textContaining('Peak'), findsNothing);
      expect(find.textContaining('Night'), findsNothing);
    });
  });

  test('surge strings have 12 languages and keep {p}', () {
    for (final e in surgeStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.contains('{p}')), isTrue, reason: e.key);
    }
  });
}
