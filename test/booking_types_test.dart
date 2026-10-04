import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/pricing/pricing_config.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/customer/post_load_screen.dart';

import 'test_utils.dart';

const rule = PricingRule(
  baseFare: 50000, perKm: 2800, minimumFare: 80000, loadingCharge: 20000, unloadingCharge: 20000,
  helperCharge: 30000, rentalPerHour: 60000, rentalKmPerHour: 10, extraKmCharge: 3000, extraHourCharge: 0,
  moversPerItem: 2500, moversPerFloor: 3000, packingPerItem: 1500,
);

void main() {
  group('helpers', () {
    test('each helper adds the configured charge; platform fee and GST follow', () {
      final none = FareCalculator.calculate(rule: rule, distanceKm: 20, platformFeePercent: 5, gstPercent: 5);
      final two = FareCalculator.calculate(rule: rule, distanceKm: 20, platformFeePercent: 5, gstPercent: 5, helpers: 2);
      expect(none.helperCharge, 0);
      expect(two.helperCharge, 60000);
      expect(two.tripFare - none.tripFare, 60000);
      expect(two.platformFee, (two.tripFare * 0.05).round());
      expect(two.total, two.tripFare + two.platformFee + two.gst);
    });

    test('0 to 4 only', () {
      expect(() => FareCalculator.calculate(rule: rule, distanceKm: 5, helpers: 5), throwsArgumentError);
      expect(() => FareCalculator.calculate(rule: rule, distanceKm: 5, helpers: -1), throwsArgumentError);
      expect(FareCalculator.calculate(rule: rule, distanceKm: 5, helpers: 4).helperCharge, 120000);
    });
  });

  group('hourly rental', () {
    test('package price and included km per hours option', () {
      for (final h in rentalHourOptions) {
        final f = FareCalculator.calculateRental(rule: rule, hours: h);
        expect(f.rentalCharge, 60000 * h);
        expect(f.extraKmCharge, 0);
        expect(f.extraHourCharge, 0);
        expect(f.tripFare, 60000 * h);
        expect(f.baseFare, 0);
      }
      expect(() => FareCalculator.calculateRental(rule: rule, hours: 6), throwsArgumentError);
    });

    test('km beyond the package and started hours beyond it are billed', () {
      // 4 h = 40 km included.
      final within = FareCalculator.calculateRental(rule: rule, hours: 4, usedKm: 40, usedMinutes: 240);
      expect(within.extraKmCharge + within.extraHourCharge, 0);
      final over = FareCalculator.calculateRental(rule: rule, hours: 4, usedKm: 55, usedMinutes: 241);
      expect(over.extraKmCharge, 15 * 3000);
      expect(over.extraHourCharge, 60000, reason: '1 started extra hour at the hourly rate');
      final twoHours = FareCalculator.calculateRental(rule: rule, hours: 4, usedMinutes: 360);
      expect(twoHours.extraHourCharge, 120000);
    });

    test('extraHourCharge overrides the hourly rate; helpers and tax are added', () {
      final r = PricingRule.fromMap({'extraHourCharge': 90000}, rule);
      final f = FareCalculator.calculateRental(rule: r, hours: 8, helpers: 1, usedMinutes: 9 * 60, platformFeePercent: 10, gstPercent: 5);
      expect(f.extraHourCharge, 90000);
      expect(f.helperCharge, 30000);
      expect(f.tripFare, 480000 + 90000 + 30000);
      expect(f.total, f.tripFare + f.platformFee + f.gst);
    });
  });

  group('packers and movers', () {
    const items = {'Sofa': 1, 'Boxes': 20};

    test('items are counted in units; floors only cost without a lift; packing is optional', () {
      const withLift = MoversDetails(items: items, floor: 4, hasLift: true, packingNeeded: false);
      final a = FareCalculator.calculate(rule: rule, distanceKm: 10, movers: withLift);
      expect(a.itemHandlingCharge, 21 * 2500);
      expect(a.floorCharge, 0);
      expect(a.packingCharge, 0);

      const stairs = MoversDetails(items: items, floor: 3, hasLift: false, packingNeeded: true);
      final b = FareCalculator.calculate(rule: rule, distanceKm: 10, movers: stairs);
      expect(b.floorCharge, 3 * 3000);
      expect(b.packingCharge, 21 * 1500);
      expect(b.tripFare - a.tripFare, 9000 + 31500);
    });

    test('item text parsing', () {
      expect(MoversDetails.parseItems('Sofa x1\nBed 2\n\nboxes X20'), {'Sofa': 1, 'Bed': 2, 'boxes': 20});
      expect(MoversDetails.parseItems('Sofa\nSofa'), {'Sofa': 2});
      expect(MoversDetails.parseItems('Chair x0'), isNull);
      expect(MoversDetails.parseItems('Chair x100'), isNull);
      expect(MoversDetails.parseItems(''), isEmpty);
    });

    test('details survive a map round trip', () {
      const d = MoversDetails(items: items, floor: 2, hasLift: false, packingNeeded: true);
      final back = MoversDetails.fromMap(d.toMap());
      expect(back.items, items);
      expect(back.floor, 2);
      expect(back.hasLift, isFalse);
      expect(back.packingNeeded, isTrue);
    });
  });

  test('breakdown round trip keeps the new lines and totals', () {
    final f = FareCalculator.calculate(
      rule: rule, distanceKm: 12, helpers: 2, platformFeePercent: 5, gstPercent: 5,
      movers: const MoversDetails(items: {'A': 2}, floor: 2, hasLift: false, packingNeeded: true),
    );
    final back = FareBreakdown.fromMap(Map<String, dynamic>.from(f.toMap()));
    expect(back.total, f.total);
    expect(back.helperCharge, f.helperCharge);
    expect(back.itemHandlingCharge, f.itemHandlingCharge);
    expect(back.floorCharge, f.floorCharge);
    expect(back.packingCharge, f.packingCharge);
    // old stored estimates (no new lines) still read
    expect(FareBreakdown.fromMap({'baseFare': 100, 'tripFare': 100, 'total': 100}).helperCharge, 0);
  });

  test('default pricing has charges for every category and can be edited by config', () {
    for (final r in defaultPricing.categories.values) {
      expect(r.helperCharge, greaterThan(0));
      expect(r.rentalPerHour, greaterThan(0));
    }
    final cfg = PricingConfig.fromMap({'categories': {'lcv': {'helperCharge': 99900}}});
    expect(cfg.categories['lcv']!.helperCharge, 99900);
    expect(cfg.categories['hcv']!.helperCharge, defaultPricing.categories['hcv']!.helperCharge);
  });

  group('posting', () {
    late FakeFirebaseFirestore db;
    setUp(() {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'c1');
      PricingService.reset();
    });

    Future<String> post({String type = BookingType.freight, int helpers = 0, int? hours, MoversDetails? movers}) => LoadService.post(
          pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null,
          pickupDate: DateTime(2026, 10, 5), notes: '', bookingType: type, helpers: helpers, rentalHours: hours, movers: movers,
        );

    test('helpers, rental hours and movers details are stored and read back', () async {
      final a = await post(helpers: 3);
      final r = await post(type: BookingType.rental, hours: 8);
      final m = await post(type: BookingType.movers, movers: const MoversDetails(items: {'Sofa': 1}, floor: 2, hasLift: false));
      Future<Load> load(String id) async => Load.fromDoc(await db.collection('loads').doc(id).get());
      expect((await load(a)).helpers, 3);
      expect((await load(a)).bookingType, BookingType.freight);
      expect((await load(r)).rentalHours, 8);
      expect((await load(r)).movers, isNull);
      final mv = await load(m);
      expect(mv.movers!.items, {'Sofa': 1});
      expect(mv.movers!.hasLift, isFalse);
      expect(mv.rentalHours, isNull);
    });

    test('bad combinations are refused', () async {
      await expectLater(post(helpers: 5), throwsArgumentError);
      await expectLater(post(type: BookingType.rental, hours: 6), throwsArgumentError);
      await expectLater(post(type: BookingType.rental), throwsArgumentError);
      await expectLater(post(type: BookingType.movers), throwsArgumentError);
      await expectLater(post(type: 'teleport'), throwsArgumentError);
      expect((await db.collection('loads').get()).docs, isEmpty);
    });

    test('old loads without the fields read as plain freight', () async {
      await db.collection('loads').doc('old').set({'shipperId': 'x', 'pickup': 'A', 'drop': 'B', 'status': 'open'});
      final l = Load.fromDoc(await db.collection('loads').doc('old').get());
      expect(l.bookingType, BookingType.freight);
      expect(l.helpers, 0);
    });
  });

  group('form', () {
    late FakeFirebaseFirestore db;
    setUp(() {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'c1');
      PricingService.reset();
      languageNotifier.value = AppLanguage.english;
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: PostLoadScreen())));
      await tester.pumpAndSettle();
    }

    double total(WidgetTester tester) {
      final t = tester.widget<Text>(find.byKey(const ValueKey('fareTotal'))).data!;
      return double.parse(t.replaceAll(RegExp(r'[^0-9.]'), ''));
    }

    testWidgets('helpers raise the estimate; rental shows the package; movers needs items', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'Delhi');
      await tester.enterText(find.byType(TextFormField).at(1), 'Jaipur');
      await tester.pumpAndSettle();
      final base = total(tester);

      await tester.tap(find.byKey(const ValueKey('helpersPlus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('helpersPlus')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('helpersValue'))).data, '2');
      expect(total(tester), greaterThan(base));

      await tester.tap(find.byKey(const ValueKey('type_rental')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rentalHours_8')), findsOneWidget);
      expect(find.byKey(const ValueKey('rentalIncludes')), findsOneWidget);
      final four = total(tester);
      await tester.tap(find.byKey(const ValueKey('rentalHours_12')));
      await tester.pumpAndSettle();
      expect(total(tester), greaterThan(four));

      await tester.tap(find.byKey(const ValueKey('type_movers')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('moversItems')), findsOneWidget);
      expect(find.byKey(const ValueKey('fareTotal')), findsNothing, reason: 'no items yet');
      await tester.enterText(find.byKey(const ValueKey('moversItems')), 'Sofa x1\nBoxes x10');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fareTotal')), findsOneWidget);
    });

    testWidgets('posting a rental with helpers stores them', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'Delhi');
      await tester.tap(find.byKey(const ValueKey('type_rental')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rentalHours_8')));
      await tester.tap(find.byKey(const ValueKey('helpersPlus')));
      await tester.pumpAndSettle();
      // weight (the field after pickup, drop)
      await tester.enterText(find.byType(TextFormField).at(2), '1');
      // pickup date
      await tester.ensureVisible(find.byIcon(Icons.calendar_today_rounded));
      await tester.tap(find.byIcon(Icons.calendar_today_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(PrimaryButton));
      await tester.tap(find.byType(PrimaryButton));
      await settle(tester);
      final docs = (await tester.runAsync(() => db.collection('loads').get()))!.docs;
      expect(docs, hasLength(1));
      final d = docs.single.data();
      expect(d['bookingType'], 'rental');
      expect(d['rentalHours'], 8);
      expect(d['helpers'], 1);
      expect(d['drop'], 'Delhi', reason: 'a rental has no separate drop');
      expect((d['estimate'] as Map)['rentalCharge'], greaterThan(0));
    });
  });
}
