import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_payment_aging_screen.dart';
import 'package:transport_app/core/admin/payment_aging.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pilot/payment_nudge_card.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-6 Task 8: payment aging and nudges.
void main() {
  final now = DateTime(2026, 10, 9, 12);
  Timestamp ago(Duration d) => Timestamp.fromDate(now.subtract(d));
  Map<String, dynamic> b({String status = 'delivered', String pay = 'pending', Duration delivered = const Duration(days: 2), Duration? marked, int? fare = 500000}) => {
        'status': status,
        'paymentStatus': pay,
        'customerId': 'c1',
        'driverId': 'd1',
        'agreedFarePaise': fare,
        'timeline': {'delivered': ago(delivered)},
        if (marked != null) 'paymentMarkedAt': ago(marked),
      };

  test('buckets by age', () {
    expect([0, 1, 2, 3, 4, 7, 8].map(PaymentAging.bucketOf), ['d0', 'd0', 'd1', 'd1', 'd3', 'd3', 'd7']);
  });

  test('aging: customer slow from delivery, driver slow from the paid mark; confirmed / undelivered skipped; oldest first', () {
    final rows = PaymentAging.compute([
      ('a', b(delivered: const Duration(days: 2))),
      ('b', b(pay: 'customer_marked_paid', delivered: const Duration(days: 9), marked: const Duration(days: 5))),
      ('c', b(pay: 'driver_confirmed')),
      ('d', b(status: 'in_transit')),
      ('e', {'status': 'delivered', 'paymentStatus': 'pending'}), // nothing to age from
      ('f', b(delivered: const Duration(days: 8), fare: null)),
    ], now);
    expect(rows.map((r) => r.bookingId), ['f', 'b', 'a']);
    expect(rows.map((r) => r.waitingOn), ['customer', 'driver', 'customer']);
    expect(rows.map((r) => r.userId), ['c1', 'd1', 'c1']);
    expect(rows[1].ageDays, 5);
    expect(rows[0].amountPaise, 0);
    expect(rows[2].amountPaise, 500000);
    expect(PaymentAging.countByBucket(rows), {'d0': 0, 'd1': 1, 'd3': 1, 'd7': 1});
  });

  test('the service reads delivered trips; a nudge is created, then counted, and audited', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    await db.collection('bookings').doc('a').set(b(delivered: const Duration(days: 3)));
    await db.collection('bookings').doc('x').set(b(status: 'accepted'));
    final rows = await AdminConsoleService.paymentAging(now: now);
    expect(rows.single.bookingId, 'a');
    await AdminConsoleService.nudgePayment(rows.single);
    var n = (await db.collection('payment_nudges').doc('a_customer').get()).data()!;
    expect((n['count'], n['userId'], n['target'], n['by']), (1, 'c1', 'customer', 'admin1'));
    await AdminConsoleService.nudgePayment(rows.single);
    n = (await db.collection('payment_nudges').doc('a_customer').get()).data()!;
    expect(n['count'], 2);
    expect((await db.collection('audit_events').get()).docs.length, 2);
  });

  testWidgets('the screen lists rows with counts and disables Remind after sending', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <String>[];
    final rows = PaymentAging.compute([('a', b(delivered: const Duration(days: 3)))], now);
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: AdminPaymentAgingScreen(load: () async => rows, nudge: (r) async => sent.add(r.bookingId)))));
    await settle(tester);
    expect(find.text('2-3 days: 1'), findsOneWidget);
    expect(find.textContaining('Waiting for the customer'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pagRemind_a_customer')));
    await settle(tester);
    expect(sent, ['a']);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('pagRemind_a_customer'))).onPressed, isNull);
  });

  testWidgets('the home card shows the person\'s own reminder for their side and clears it', (tester) async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
    await db.collection('payment_nudges').doc('a_customer').set({'bookingId': 'a', 'userId': 'c1', 'target': 'customer', 'count': 1});
    await db.collection('payment_nudges').doc('b_driver').set({'bookingId': 'b', 'userId': 'c1', 'target': 'driver', 'count': 1});
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: Scaffold(body: PaymentNudgeCard(target: 'customer')))));
    await settle(tester);
    expect(find.byKey(const ValueKey('paymentNudgeCard')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paymentNudgeClear')));
    await settle(tester);
    expect(find.byKey(const ValueKey('paymentNudgeCard')), findsNothing);
    expect((await db.collection('payment_nudges').get()).docs.map((d) => d.id), ['b_driver']);
  });
}
