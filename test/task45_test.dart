import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/trip_cost_strings.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/pricing/pricing_config.dart';
import 'package:transport_app/core/pricing/trip_cost.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/widgets/common.dart' show formatPaise;
import 'package:transport_app/core/widgets/logistics_labels.dart';
import 'package:transport_app/core/widgets/trip_cost_widgets.dart';

void main() {
  setUp(() => languageNotifier.value = AppLanguage.english);

  group('TollTable', () {
    test('a known corridor uses its fixed figure, scaled by category', () {
      expect(TollTable.estimate(from: 'Delhi', to: 'Jaipur', category: 'lcv', km: 297), 70000);
      expect(TollTable.estimate(from: 'Jaipur, Rajasthan', to: 'new delhi', category: 'lcv', km: 297), 70000, reason: 'order and spelling do not matter');
      expect(TollTable.estimate(from: 'Delhi', to: 'Jaipur', category: 'hcv', km: 297), 140000);
      expect(TollTable.estimate(from: 'Delhi', to: 'Jaipur', category: 'trailer', km: 297), 280000);
    });

    test('two and three wheelers pay no toll', () {
      expect(TollTable.estimate(from: 'Delhi', to: 'Jaipur', category: 'two_wheeler', km: 297), 0);
      expect(TollTable.estimate(from: 'Pune', to: 'Nashik', category: 'three_wheeler', km: 200), 0);
    });

    test('an unknown route falls back to the per-km average', () {
      expect(TollTable.estimate(from: 'Salem', to: 'Madurai', category: 'lcv', km: 100), 12000);
      expect(TollTable.estimate(from: 'Nowhere', to: 'Else', category: 'hcv', km: 100), 24000);
      expect(TollTable.estimate(from: 'Salem', to: 'Madurai', category: 'weird', km: 100), 12000, reason: 'unknown category acts as lcv');
    });

    test('a wrong short distance clamps a corridor figure to 3x the per-km value', () {
      // 10 km at 120 paise = 1200; 3x = 3600 < 70000.
      expect(TollTable.estimate(from: 'Delhi', to: 'Jaipur', category: 'lcv', km: 10), 3600);
    });

    test('zero or negative distance has no toll', () {
      expect(TollTable.estimate(from: 'Delhi', to: 'Jaipur', category: 'lcv', km: 0), 0);
      expect(TollTable.estimate(from: 'Delhi', to: 'Jaipur', category: 'lcv', km: -5), 0);
    });
  });

  group('FuelEstimate', () {
    test('cost in paise, half up', () {
      // 120 km / 12 kmpl = 10 L x Rs 90 = Rs 900.
      expect(FuelEstimate.cost(km: 120, category: 'lcv'), 90000);
      // 100 km / 4 kmpl = 25 L x 9000 = 225000.
      expect(FuelEstimate.cost(km: 100, category: 'hcv'), 225000);
      expect(FuelEstimate.cost(km: 100, category: 'lcv', dieselPaisePerLitre: 10000), 83333);
      expect(FuelEstimate.cost(km: 1, category: 'lcv', dieselPaisePerLitre: 9005), 750, reason: '750.4 rounds to 750');
    });

    test('litres in tenths round up; empty inputs cost nothing', () {
      expect(FuelEstimate.litresTenths(120, 'lcv'), 100);
      expect(FuelEstimate.litresTenths(100, 'lcv'), 84);
      expect(FuelEstimate.cost(km: 0, category: 'lcv'), 0);
      expect(FuelEstimate.cost(km: 50, category: 'lcv', dieselPaisePerLitre: 0), 0);
    });
  });

  group('TripCostPreview', () {
    test('combines fare, toll and fuel', () {
      final p = TripCostPreview.compute(farePaise: 500000, km: 297, category: 'lcv', from: 'Delhi', to: 'Jaipur');
      expect(p.tollPaise, 70000);
      expect(p.fuelPaise, FuelEstimate.cost(km: 297, category: 'lcv'));
      expect(p.total, p.farePaise + p.tollPaise + p.fuelPaise);
      expect(p.netMargin, p.farePaise - p.tollPaise - p.fuelPaise);
    });

    test('a bid below the running cost gives a negative margin', () {
      final p = TripCostPreview.compute(farePaise: 0, km: 297, category: 'lcv', from: 'Delhi', to: 'Jaipur');
      expect(p.withFare(10000).netMargin, isNegative);
      expect(p.withFare(10000).tollPaise, p.tollPaise);
    });
  });

  group('config', () {
    test('diesel price defaults, reads, ignores nonsense and round-trips', () {
      expect(defaultPricing.dieselPaisePerLitre, FuelEstimate.defaultDieselPaisePerLitre);
      expect(PricingConfig.fromMap({'dieselPaisePerLitre': 10250}).dieselPaisePerLitre, 10250);
      expect(PricingConfig.fromMap({'dieselPaisePerLitre': -4}).dieselPaisePerLitre, 9000);
      expect(PricingConfig.fromMap({'dieselPaisePerLitre': 'x'}).dieselPaisePerLitre, 9000);
      expect(PricingConfig.fromMap(PricingConfig.fromMap({'dieselPaisePerLitre': 9900}).toMap()).dieselPaisePerLitre, 9900);
    });
  });

  group('widgets', () {
    Widget app(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: SingleChildScrollView(child: child))));

    testWidgets('customer card marks every line as an estimate', (t) async {
      final cost = TripCostPreview.compute(farePaise: 500000, km: 297, category: 'lcv', from: 'Delhi', to: 'Jaipur');
      await t.pumpWidget(app(TripCostCard(cost: cost)));
      expect(find.text('Fare (estimate)'), findsOneWidget);
      expect(find.text('Toll (estimate)'), findsOneWidget);
      expect(find.text('Diesel (estimate)'), findsOneWidget);
      expect(find.text('Fare + toll + diesel (estimate)'), findsOneWidget);
      expect(find.byKey(const ValueKey('tripCostTotal')), findsOneWidget);
    });

    testWidgets('the bid dialog shows toll, diesel and the margin as the driver types', (t) async {
      final cost = TripCostPreview.compute(farePaise: 0, km: 297, category: 'lcv', from: 'Delhi', to: 'Jaipur');
      await t.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () => askPricePaise(context, title: 'Offer', label: 'Price', footer: (c, p) => BidMarginPanel(cost: cost, bidPaise: p)),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Toll (estimate)'), findsOneWidget);
      expect(find.byKey(const ValueKey('bidNet')), findsNothing);
      await t.enterText(find.byKey(const ValueKey('priceField')), '10000');
      await t.pump();
      final net = 1000000 - cost.runningCost;
      expect(find.byKey(const ValueKey('bidNet')), findsOneWidget);
      expect(find.text(formatPaise(net)), findsOneWidget);
    });

    testWidgets('the helper uses the admin diesel price', (t) async {
      Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'u');
      PricingService.notifier.value = PricingConfig(categories: defaultPricing.categories, dieselPaisePerLitre: 12000);
      addTearDown(PricingService.reset);
      final c = tripCostFor(farePaise: 1, km: 120, vehicleType: 'Mini', from: 'Salem', to: 'Madurai');
      expect(c.fuelPaise, FuelEstimate.cost(km: 120, category: 'lcv', dieselPaisePerLitre: 12000));
    });
  });

  test('load without a distance has no panel inputs (estimate key stays optional)', () {
    final load = Load(
      id: 'L', shipperId: 'c', pickup: 'Zzz', drop: 'Yyy', cargoType: 'x', weight: 1, vehicleType: '20ft', budget: null,
      pickupDate: DateTime(2026, 10, 6), notes: '', status: 'open', createdAt: Timestamp.now(),
    );
    expect(PricingService.estimateRouteKm(load.route), isNull);
  });

  test('strings have 12 non-empty languages', () {
    for (final e in tripCostStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.isNotEmpty), isTrue, reason: e.key);
    }
  });
}
