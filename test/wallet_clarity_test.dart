import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/payments/payment_timeline.dart';
import 'package:transport_app/core/payments/wallet_insight.dart';
import 'package:transport_app/core/payments/wallet_widgets.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/support/support_screens.dart';

import 'test_utils.dart';

/// MASTER-6 Task 25: wallet and ledger clarity.
void main() {
  Booking trip(String id, {String status = 'delivered', String pay = 'pending', DateTime? delivered, int? paid}) => Booking(
        id: id, loadId: id, driverId: 'd1', vehicleId: 'v', customerId: 'c', status: status, pickup: 'Delhi', drop: 'Jaipur', cargoType: 'x', weight: 1,
        vehicleType: '20ft', budget: 5000, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1',
        timeline: {'delivered': ?delivered}, paymentStatus: pay, paidAmountPaise: paid,
      );

  LedgerEntry line(String type, int paise, {String booking = 'b1'}) => LedgerEntry(id: '${booking}_$type', driverId: 'd1', bookingId: booking, type: type, amountPaise: paise, createdAt: DateTime(2026, 10, 9));

  test('waiting: only delivered and unconfirmed; driver turn first, then oldest delivery', () {
    final w = WalletInsight.waiting([
      trip('a', pay: 'pending', delivered: DateTime(2026, 10, 1)),
      trip('b', pay: 'customer_marked_paid', delivered: DateTime(2026, 10, 5)),
      trip('c', pay: 'driver_confirmed', delivered: DateTime(2026, 10, 2)),
      trip('d', status: 'in_transit'),
      trip('e', pay: 'pending', delivered: DateTime(2026, 9, 25)),
    ]);
    expect(w.map((x) => x.booking.id), ['b', 'e', 'a']);
    expect(w.map((x) => x.next), [PaymentNext.confirmReceived, PaymentNext.waitCustomer, PaymentNext.waitCustomer]);
    expect(WalletInsight.waitingTotal(w), 3 * 500000);
    expect(WalletInsight.waiting(const []), isEmpty);
  });

  test('commission percent: of the same booking, rounded; null when a line is missing', () {
    final all = [line('trip_earning', 500000), line('platform_commission', -50000), line('trip_earning', 200000, booking: 'b2')];
    expect(WalletInsight.commissionPercent(all, 'b1'), 10);
    expect(WalletInsight.commissionPercent(all, 'b2'), isNull);
    expect(WalletInsight.commissionPercent(all, 'nope'), isNull);
    expect(WalletInsight.commissionPercent([line('trip_earning', 300000), line('platform_commission', -10000)], 'b1'), 3);
  });

  testWidgets('the waiting card lists the trips with whose turn it is and opens one on tap', (tester) async {
    String? opened;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WalletWaitingCard(bookings: [trip('a', delivered: DateTime(2026, 10, 1)), trip('b', pay: 'customer_marked_paid', delivered: DateTime(2026, 10, 5))], onOpen: (c, id) => opened = id)))),
    ));
    expect(find.textContaining('Money on its way: ₹'), findsOneWidget);
    expect(find.textContaining('Your turn'), findsOneWidget);
    expect(find.textContaining('Waiting for the customer'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('waiting_b')));
    expect(opened, 'b');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: WalletWaitingCard(bookings: [trip('c', pay: 'driver_confirmed')])))));
    expect(find.byKey(const ValueKey('walletWaiting')), findsNothing);
  });

  testWidgets('a ledger line explains itself and Question this line opens a payment ticket for the trip', (tester) async {
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'd1');
    final all = [line('trip_earning', 500000), line('platform_commission', -50000)];
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showLedgerLine(c, all[1], all), child: const Text('open'))))),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.textContaining('About 10% of the fare'), findsOneWidget);
    expect(find.textContaining('recorded when you confirmed'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ledgerQuestion')));
    await settle(tester);
    expect(find.byType(NewTicketScreen), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Question about Platform commission on LG-B1'), findsOneWidget);
    expect(find.textContaining('Amount'), findsWidgets);
  });
}
