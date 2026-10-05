import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/driver_extras.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/wallet/txn_history.dart';
import 'package:transport_app/core/wallet/txn_history_screen.dart';

import 'test_utils.dart';

Booking trip(String id, DateTime at, int paise, {String pay = 'pending'}) => Booking(
      id: id, loadId: id, driverId: 'd1', vehicleId: 'v', customerId: 'c1', status: 'delivered', pickup: 'Pune', drop: 'Delhi', cargoType: 'x',
      weight: 1, vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1',
      timeline: {'delivered': at}, agreedFarePaise: paise, paymentStatus: pay,
    );

void main() {
  final now = DateTime.now();
  final d1 = now.subtract(const Duration(days: 2)), d2 = now.subtract(const Duration(days: 40)), d3 = now.subtract(const Duration(days: 200));

  final driverLines = TxnHistory.forDriver(
    ledger: [
      LedgerEntry(id: 'b1_trip_earning', driverId: 'd1', bookingId: 'b1', type: LedgerType.tripEarning, amountPaise: 100000, createdAt: d1),
      LedgerEntry(id: 'b1_platform_commission', driverId: 'd1', bookingId: 'b1', type: LedgerType.platformCommission, amountPaise: -10000, createdAt: d1),
      LedgerEntry(id: 'b2_trip_earning', driverId: 'd1', bookingId: 'b2', type: LedgerType.tripEarning, amountPaise: 50000, createdAt: d2),
    ],
    payouts: [
      Payout(id: 'p1', driverId: 'd1', amountPaise: 30000, status: Payout.paid, createdAt: d1),
      Payout(id: 'p2', driverId: 'd1', amountPaise: 20000, status: Payout.requested, createdAt: d1),
      Payout(id: 'p3', driverId: 'd1', amountPaise: 99900, status: Payout.rejected, createdAt: d1),
    ],
    tips: [Tip(bookingId: 'b1', driverId: 'd1', amountPaise: 5000, createdAt: d3)],
  );

  test('driver lines: signed amounts, rejected payouts skipped, newest first, pending not summed', () {
    expect(driverLines.length, 6);
    expect(driverLines.last.kind, TxnKind.tip);
    final s = TxnHistory.summary(driverLines);
    expect((s.moneyIn, s.moneyOut, s.net), (155000, -40000, 115000)); // pending payout of 20000 not counted
    expect(driverLines.where((l) => l.pending).single.amountPaise, -20000);
  });

  test('filters by kind, direction and period', () {
    expect(TxnHistory.apply(driverLines, const TxnFilter(kinds: {TxnKind.payout})).length, 2);
    expect(TxnHistory.apply(driverLines, const TxnFilter(direction: TxnDirection.moneyOut)).length, 3);
    expect(TxnHistory.apply(driverLines, TxnFilter(from: now.subtract(const Duration(days: 30)))).length, 4);
    expect(TxnHistory.apply(driverLines, TxnFilter(kinds: {TxnKind.earning}, from: now.subtract(const Duration(days: 90)))).length, 2);
  });

  test('customer lines: delivered trips are money out, pending until the driver confirms; credits and tips', () {
    final lines = TxnHistory.forCustomer(
      bookings: [trip('b1', d1, 250000, pay: 'driver_confirmed'), trip('b2', d2, 100000)],
      tips: [Tip(bookingId: 'b1', driverId: 'd1', customerId: 'c1', amountPaise: 5000, createdAt: d1.add(const Duration(hours: 1)))],
      credits: [CreditLine(id: 'c1', amountPaise: 20000, kind: 'grant', createdAt: d3)],
    );
    expect(lines.map((l) => (l.kind, l.amountPaise, l.pending)).toList(), [
      ('tip', -5000, false),
      ('trip', -250000, false),
      ('trip', -100000, true),
      ('credit', 20000, false),
    ]);
    final s = TxnHistory.summary(lines);
    expect((s.moneyIn, s.moneyOut), (20000, -255000));
  });

  test('CSV: header, signed rupees, status', () {
    final csv = TxnHistory.toCsv(driverLines).split('\n');
    expect(csv.first, 'date,type,booking,status,amount_rupees');
    expect(csv.length, 7);
    expect(csv.any((r) => r.endsWith('commission,b1,settled,-100.00')), isTrue);
    expect(csv.any((r) => r.endsWith(',payout,,pending,-200.00')), isTrue);
    expect(TxnHistory.toCsv(const []), 'date,type,booking,status,amount_rupees');
  });

  testWidgets('driver screen: shows lines, filters, copies CSV', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'd1');
    await db.collection('ledger').doc('b1_trip_earning').set({'driverId': 'd1', 'bookingId': 'b1', 'type': 'trip_earning', 'amountPaise': 100000, 'createdAt': Timestamp.fromDate(d1)});
    await db.collection('ledger').doc('b1_platform_commission').set({'driverId': 'd1', 'bookingId': 'b1', 'type': 'platform_commission', 'amountPaise': -10000, 'createdAt': Timestamp.fromDate(d1)});
    await db.collection('payouts').doc('p1').set({'driverId': 'd1', 'amountPaise': 30000, 'status': 'paid', 'createdAt': Timestamp.fromDate(d1)});
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(const MaterialApp(home: TxnHistoryScreen(isDriver: true)));
    await settle(tester);
    expect(find.byKey(const ValueKey('txn_l_b1_trip_earning')), findsOneWidget);
    expect(find.byKey(const ValueKey('txn_p_p1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('txnKind_payout')));
    await settle(tester);
    expect(find.byKey(const ValueKey('txn_l_b1_trip_earning')), findsNothing);
    expect(find.byKey(const ValueKey('txn_p_p1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('txnCsv')));
    await settle(tester);
    expect(copied, contains('payout'));
    expect(copied, isNot(contains('earning')));
  });
}
