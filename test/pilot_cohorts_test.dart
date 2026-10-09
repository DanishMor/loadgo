import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_cohorts_screen.dart';
import 'package:transport_app/core/admin/pilot_cohorts.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-6 Task 6: weekly cohorts of loads.
void main() {
  final mon = DateTime(2026, 10, 5, 10); // a Monday
  final nextMon = DateTime(2026, 10, 12, 10);

  test('week starts on Monday (Sunday belongs to the week before)', () {
    expect(PilotCohorts.weekStart(DateTime(2026, 10, 11, 23)), DateTime(2026, 10, 5));
    expect(PilotCohorts.weekStart(DateTime(2026, 10, 5)), DateTime(2026, 10, 5));
    expect(PilotCohorts.weekStart(DateTime(2026, 3, 1)), DateTime(2026, 2, 23));
  });

  test('median of odd, even and empty lists', () {
    expect(PilotCohorts.median([5, 1, 3]), 3);
    expect(PilotCohorts.median([1, 2, 3, 10]), 2);
    expect(PilotCohorts.median([]), isNull);
  });

  test('cohorts: first bid, fill, repeat customers, cancel reasons', () {
    final rows = PilotCohorts.compute(
      [
        CohortLoad('l1', 'c1', mon),
        CohortLoad('l2', 'c2', mon.add(const Duration(hours: 1))),
        CohortLoad('l3', 'c1', nextMon), // c1 comes back
      ],
      [
        CohortOffer('l1', mon.add(const Duration(minutes: 20))),
        CohortOffer('l1', mon.add(const Duration(minutes: 5))),
        CohortOffer('l3', nextMon.add(const Duration(minutes: 50))),
      ],
      [
        CohortBooking('l1', mon.add(const Duration(minutes: 90)), 'delivered'),
        CohortBooking('l2', mon.add(const Duration(hours: 3)), 'cancelled', 'price_high'),
        CohortBooking('l2', mon.add(const Duration(hours: 4)), 'cancelled', 'made_up_code'),
      ],
    );
    expect(rows.map((r) => r.week), [DateTime(2026, 10, 12), DateTime(2026, 10, 5)]); // newest first
    final w1 = rows[1];
    expect((w1.loads, w1.withBid, w1.filled), (2, 1, 1));
    expect(w1.medianFirstBidMinutes, 5);
    expect(w1.medianFillMinutes, 90);
    expect((w1.customers, w1.repeatCustomers, w1.repeatPercent), (2, 1, 50));
    expect(w1.cancelReasons, {'price_high': 1, 'none': 1});
    final w2 = rows[0];
    expect((w2.loads, w2.filled, w2.medianFillMinutes), (1, 0, null));
    expect(w2.repeatCustomers, 1);
  });

  test('a clock skew never gives negative minutes', () {
    final rows = PilotCohorts.compute([CohortLoad('l1', 'c1', mon)], [CohortOffer('l1', mon.subtract(const Duration(minutes: 3)))], const []);
    expect(rows.single.medianFirstBidMinutes, 0);
  });

  test('CSV: header, one row per week, counts only', () {
    final rows = PilotCohorts.compute([CohortLoad('l1', 'c1', mon)], const [], [CohortBooking('l1', mon, 'cancelled', 'plan_changed')]);
    final lines = PilotCohorts.toCsv(rows).split('\n');
    expect(lines.first, startsWith('week,loads,with_bid,filled,median_first_bid_min,median_fill_min,customers'));
    expect(lines.first, contains('cancel_plan_changed'));
    expect(lines.length, 2);
    expect(lines[1], startsWith('2026-10-05,1,0,0,,,1,0,0,'));
    expect(lines.first.split(',').length, lines[1].split(',').length);
  });

  test('the service reads loads, offers and bookings', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'a');
    Timestamp t(DateTime d) => Timestamp.fromDate(d);
    await db.collection('loads').doc('l1').set({'shipperId': 'c1', 'createdAt': t(mon)});
    await db.collection('offers').doc('o1').set({'loadId': 'l1', 'createdAt': t(mon.add(const Duration(minutes: 10)))});
    await db.collection('bookings').doc('b1').set({'loadId': 'l1', 'status': 'cancelled', 'createdAt': t(mon.add(const Duration(hours: 1))), 'cancellation': {'by': 'customer', 'reason': 'price_high', 'chargePaise': 0}});
    final rows = await AdminConsoleService.pilotCohorts();
    expect(rows.single.medianFirstBidMinutes, 10);
    expect(rows.single.cancelReasons, {'price_high': 1});
  });

  testWidgets('the screen shows a card per week and the cancel reasons in words', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rows = PilotCohorts.compute([CohortLoad('l1', 'c1', mon)], [CohortOffer('l1', mon.add(const Duration(minutes: 150)))], [CohortBooking('l1', mon, 'cancelled', 'price_high')]);
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: AdminCohortsScreen(load: () async => rows))));
    await settle(tester);
    expect(find.text('Week of 2026-10-05'), findsOneWidget);
    expect(find.textContaining('2 h 30 min'), findsOneWidget);
    expect(find.textContaining('Price is too high: 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('cohCsv')), findsOneWidget);
  });

  testWidgets('no loads shows the empty state', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: AdminCohortsScreen(load: () async => const []))));
    await settle(tester);
    expect(find.textContaining('No loads yet'), findsOneWidget);
  });
}
