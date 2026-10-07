import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_unit_economics_screen.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/analytics/unit_economics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/unit_economics_strings.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

Booking bk(String id, String status, int paise, DateTime at) => Booking.fromMap(id, {
      'driverId': 'd1', 'customerId': 'c1', 'status': status, 'pickup': 'Delhi', 'drop': 'Jaipur', 'agreedFarePaise': paise, 'createdAt': Timestamp.fromDate(at),
    });

void main() {
  final now = DateTime(2026, 10, 7, 12);
  late FakeFirebaseFirestore db;

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
  });

  group('UnitEconomics.compute', () {
    final today = DateTime(2026, 10, 6, 9);
    final list = [
      bk('a', 'delivered', 1000000, today),
      bk('b', 'delivered', 500000, today),
      bk('c', 'cancelled', 400000, today),
      bk('d', 'in_transit', 300000, today),
      bk('old', 'delivered', 900000, DateTime(2026, 8, 1)),
    ];
    final lines = <CommissionLine>[(at: today, paise: 50000), (at: today, paise: 25000), (at: DateTime(2026, 8, 1), paise: 99999), (at: today, paise: -5)];

    test('figures for the period, old bookings and lines are left out', () {
      final u = UnitEconomics.compute(list, lines, costs: const EconomicsCosts(), now: now);
      expect((u.trips, u.bookings, u.cancelled), (2, 4, 1));
      expect(u.deliveredValuePaise, 1500000);
      expect(u.revenuePaise, 75000, reason: 'only positive lines inside the period');
      expect(u.avgFarePaise, 750000);
      expect(u.revenuePerTripPaise, 37500);
      expect(u.takeRateBp, 500, reason: '5.00%');
      expect(u.cancelRate, 0.25);
    });

    test('costs: contribution, result and break-even', () {
      final u = UnitEconomics.compute(list, lines, costs: const EconomicsCosts(monthlyFixedPaise: 1000000, perTripCostPaise: 7500), now: now);
      expect(u.contributionPerTripPaise, 30000);
      expect(u.profitPaise, 75000 - 2 * 7500 - 1000000);
      expect(u.breakEvenTrips, 34, reason: 'ceil(1,000,000 / 30,000)');
    });

    test('a trip that costs more than it earns has no break-even', () {
      final u = UnitEconomics.compute(list, lines, costs: const EconomicsCosts(monthlyFixedPaise: 100, perTripCostPaise: 37500), now: now);
      expect(u.contributionPerTripPaise, 0);
      expect(u.breakEvenTrips, isNull);
    });

    test('no data: nothing divides by zero', () {
      final u = UnitEconomics.compute(const [], const [], costs: const EconomicsCosts(monthlyFixedPaise: 500), now: now);
      expect((u.avgFarePaise, u.revenuePerTripPaise, u.takeRateBp, u.cancelRate, u.contributionPerTripPaise, u.breakEvenTrips), (null, null, null, null, null, null));
      expect(u.profitPaise, -500);
    });

    test('costs parse safely', () {
      final c = EconomicsCosts.fromMap({'monthlyFixedPaise': 12345, 'perTripCostPaise': -5});
      expect((c.monthlyFixedPaise, c.perTripCostPaise), (12345, 0));
      expect(EconomicsCosts.fromMap(null).monthlyFixedPaise, 0);
      expect(EconomicsCosts.fromMap({'monthlyFixedPaise': 'x'}).monthlyFixedPaise, 0);
    });
  });

  group('AdminConsoleService.unitEconomics', () {
    test('reads bookings, commission lines and the saved costs', () async {
      final at = DateTime(2026, 10, 6, 9);
      await db.collection('bookings').doc('b1').set({'driverId': 'd1', 'customerId': 'c1', 'status': 'delivered', 'pickup': 'A', 'drop': 'B', 'agreedFarePaise': 1000000, 'createdAt': Timestamp.fromDate(at)});
      await db.collection('ledger').doc('b1_platform_commission').set({'driverId': 'd1', 'bookingId': 'b1', 'type': 'platform_commission', 'amountPaise': -50000, 'createdAt': Timestamp.fromDate(at)});
      await db.collection('ledger').doc('b1_trip_earning').set({'driverId': 'd1', 'bookingId': 'b1', 'type': 'trip_earning', 'amountPaise': 1000000, 'createdAt': Timestamp.fromDate(at)});
      await db.collection('config').doc('economics').set({'monthlyFixedPaise': 20000, 'perTripCostPaise': 1000});
      final u = await AdminConsoleService.unitEconomics(now: now);
      expect((u.trips, u.revenuePaise), (1, 50000));
      expect((u.costs.monthlyFixedPaise, u.costs.perTripCostPaise), (20000, 1000));
      expect(u.profitPaise, 50000 - 1000 - 20000);
    });

    test('saving the costs writes config/economics with an audit row', () async {
      await AdminConsoleService.saveEconomicsCosts(const EconomicsCosts(monthlyFixedPaise: 100, perTripCostPaise: 5));
      expect((await db.collection('config').doc('economics').get()).data()!['monthlyFixedPaise'], 100);
      expect((await db.collection('audit_events').where('type', isEqualTo: 'config_change').get()).docs.single['targetId'], 'economics');
    });
  });

  group('AdminUnitEconomicsScreen', () {
    UnitEconomics sample() => UnitEconomics.compute(
          [bk('a', 'delivered', 1000000, DateTime(2026, 10, 6)), bk('b', 'cancelled', 1, DateTime(2026, 10, 6))],
          [(at: DateTime(2026, 10, 6), paise: 50000)],
          costs: const EconomicsCosts(monthlyFixedPaise: 100000, perTripCostPaise: 2500),
          now: now,
        );

    Future<void> open(WidgetTester t, {Future<void> Function(EconomicsCosts)? save}) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: AdminUnitEconomicsScreen(load: () async => sample(), save: save))));
      await settle(t);
    }

    String text(WidgetTester t, String k) => t.widget<Text>(find.byKey(ValueKey('ue_$k'))).data!;

    testWidgets('shows the figures and fills the cost fields', (t) async {
      await open(t);
      expect(text(t, 'trips'), '1');
      expect(text(t, 'cancelRate'), '50.0%');
      expect(text(t, 'takeRate'), '5.00%');
      expect(t.widget<TextField>(find.byKey(const ValueKey('ueFixed'))).controller!.text, '1000');
      expect(t.widget<TextField>(find.byKey(const ValueKey('uePerTrip'))).controller!.text, '25');
      expect(find.text('Trips needed to cover fixed cost'), findsOneWidget);
    });

    testWidgets('save sends the typed costs in paise; bad text is refused', (t) async {
      EconomicsCosts? sent;
      await open(t, save: (c) async => sent = c);
      await t.enterText(find.byKey(const ValueKey('ueFixed')), '2500.50');
      await t.enterText(find.byKey(const ValueKey('uePerTrip')), '40');
      await t.tap(find.byKey(const ValueKey('ueSave')));
      await settle(t);
      expect((sent!.monthlyFixedPaise, sent!.perTripCostPaise), (250050, 4000));
      sent = null;
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('ueFixed')), '');
      await t.tap(find.byKey(const ValueKey('ueSave')));
      await settle(t);
      expect(sent, isNull);
      expect(find.text('Enter a number in rupees (0 or more)'), findsOneWidget);
    });
  });

  test('staff area: super admin only', () {
    expect(staffCan('super', 'adminUnitEconomics'), isTrue);
    for (final r in ['support', 'ops', 'verifier']) {
      expect(staffCan(r, 'adminUnitEconomics'), isFalse);
    }
  });

  test('unit economics strings: 12 languages, same placeholders', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in unitEconomicsStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
      for (var i = 1; i < 12; i++) {
        expect(ph.allMatches(e.value[i]).map((m) => m[1]).toSet(), want, reason: '${e.key}/$i');
      }
    }
  });
}
