import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/earnings.dart';
import 'package:transport_app/features/earnings/earnings_view.dart';

import 'test_utils.dart';

/// Thursday 8 Oct 2026, 15:00 — week started Monday 5 Oct.
final now = DateTime(2026, 10, 8, 15);

Future<Booking> booking(FakeFirebaseFirestore db, String id,
    {required String status, num? budget, DateTime? deliveredAt}) async {
  await db.collection('bookings').doc(id).set({
    'driverId': 'driver1',
    'customerId': 'customer1',
    'status': status,
    'pickup': 'P$id',
    'drop': 'D$id',
    'budget': budget,
    'timeline': {'delivered': ?(deliveredAt == null ? null : Timestamp.fromDate(deliveredAt))},
  });
  return Booking.fromDoc(await db.collection('bookings').doc(id).get());
}

void main() {
  test('startOfWeek is Monday 00:00', () {
    expect(EarningsSummary.startOfWeek(now), DateTime(2026, 10, 5));
    expect(EarningsSummary.startOfWeek(DateTime(2026, 10, 5, 0, 1)), DateTime(2026, 10, 5));
    expect(EarningsSummary.startOfWeek(DateTime(2026, 10, 11, 23)), DateTime(2026, 10, 5));
  });

  test('sums delivered trips only, splitting today / this week / total', () async {
    final db = FakeFirebaseFirestore();
    final list = [
      await booking(db, 'a', status: 'delivered', budget: 10000, deliveredAt: DateTime(2026, 10, 8, 9)), // today
      await booking(db, 'b', status: 'delivered', budget: 5000, deliveredAt: DateTime(2026, 10, 5, 1)), // this week
      await booking(db, 'c', status: 'delivered', budget: 7000, deliveredAt: DateTime(2026, 10, 4, 23)), // last week
      await booking(db, 'd', status: 'delivered', budget: null, deliveredAt: DateTime(2026, 10, 6)), // negotiable
      await booking(db, 'e', status: 'in_transit', budget: 9999),
      await booking(db, 'f', status: 'cancelled', budget: 9999),
    ];
    final e = EarningsSummary.from(list, now);
    expect(e.total, 22000);
    expect(e.thisWeek, 15000);
    expect(e.today, 10000);
    expect(e.completedTrips, 4);
    expect(e.delivered.map((b) => b.id), ['a', 'd', 'b', 'c']);
  });

  testWidgets('earnings tab shows totals and completed trips', (tester) async {
    final db = FakeFirebaseFirestore();
    late List<Booking> list;
    await tester.runAsync(() async {
      list = [
        await booking(db, 'a', status: 'delivered', budget: 10000, deliveredAt: DateTime(2026, 10, 8, 9)),
        await booking(db, 'c', status: 'delivered', budget: 7000, deliveredAt: DateTime(2026, 10, 1)),
      ];
    });
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EarningsView(bookings: () => Stream.value(list), onOpenTrip: (id) => opened = id, now: () => now)),
    ));
    await settle(tester);
    expect(find.text('₹ 17000'), findsOneWidget);
    expect(find.text('₹ 10000'), findsNWidgets(2), reason: 'this week + trip row');
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('Pa → Da'));
    expect(opened, 'a');
  });

  testWidgets('empty state when nothing delivered', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EarningsView(bookings: () => Stream.value(const <Booking>[]), onOpenTrip: (_) {}, now: () => now)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No completed trips yet'), findsOneWidget);
    expect(find.text('₹ 0'), findsNWidgets(2));
  });
}
