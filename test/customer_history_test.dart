import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/features/bookings/customer_bookings_view.dart';
import 'package:transport_app/core/documents/invoice_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'customer1');
  });

  Future<void> seed(String id, String status, {num? budget = 25000}) => db.collection('bookings').doc(id).set({
        'loadId': 'L$id',
        'driverId': 'driver1',
        'customerId': 'customer1',
        'status': status,
        'pickup': 'From$id',
        'drop': 'To$id',
        'cargoType': 'FMCG',
        'weight': 8,
        'vehicleType': '20ft',
        'budget': budget,
        'vehicleNumber': 'MH12AB1234',
        'driverName': 'Ramesh',
        'timeline': {'delivered': Timestamp.fromDate(DateTime(2026, 10, 7))},
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });

  testWidgets('active vs past tabs; delivered opens invoice, others open tracking', (tester) async {
    await tester.runAsync(() async {
      await seed('a', 'in_transit');
      await seed('b', 'delivered');
      await seed('c', 'cancelled');
    });
    String? tracking, invoice;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomerBookingsView(
          bookings: BookingService.watchForCustomerPage,
          onOpenTracking: (id) => tracking = id,
          onOpenInvoice: (id) => invoice = id,
        ),
      ),
    ));
    await settle(tester);
    expect(find.text('Froma → Toa'), findsOneWidget);
    expect(find.text('Fromb → Tob'), findsNothing);

    await tester.tap(find.text('Past'));
    await settle(tester);
    expect(find.text('Froma → Toa'), findsNothing);
    expect(find.text('Fromb → Tob'), findsOneWidget);
    expect(find.text('Fromc → Toc'), findsOneWidget);
    expect(find.text('View invoice'), findsOneWidget, reason: 'only delivered bookings have invoices');

    await tester.tap(find.text('View invoice'));
    expect(invoice, 'b');
    await tester.tap(find.text('Fromc → Toc'));
    expect(tracking, 'c');
  });

  testWidgets('past tab empty state', (tester) async {
    await tester.runAsync(() => seed('a', 'accepted'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomerBookingsView(
            bookings: BookingService.watchForCustomerPage, onOpenTracking: (_) {}, onOpenInvoice: (_) {}),
      ),
    ));
    await settle(tester);
    await tester.tap(find.text('Past'));
    await settle(tester);
    expect(find.text('No past bookings yet'), findsOneWidget);
  });

  testWidgets('invoice shows trip summary and fare', (tester) async {
    await tester.runAsync(() => seed('abcdefghij', 'delivered'));
    await tester.pumpWidget(const MaterialApp(home: InvoiceScreen(bookingId: 'abcdefghij')));
    await settle(tester);
    expect(find.text('LG-ABCDEFGH'), findsOneWidget);
    expect(find.text('7 Oct 2026'), findsOneWidget);
    expect(find.text('Fromabcdefghij'), findsOneWidget);
    expect(find.text('Toabcdefghij'), findsOneWidget);
    expect(find.text('Ramesh'), findsOneWidget);
    expect(find.text('MH12AB1234 (20 ft truck)'), findsOneWidget);
    // Budget ₹25,000 is billed GST-inclusive (5%): taxable ₹23,809.52 + CGST/SGST.
    expect(find.byKey(const ValueKey('invoiceTotal')), findsOneWidget);
    expect(find.text('₹ 25,000'), findsOneWidget);
    expect(find.text('₹ 23,809.52'), findsOneWidget);
    expect(find.text('CGST (2.5%)'), findsOneWidget);
  });

  testWidgets('invoice is unavailable before delivery', (tester) async {
    await tester.runAsync(() => seed('x', 'in_transit'));
    await tester.pumpWidget(const MaterialApp(home: InvoiceScreen(bookingId: 'x')));
    await settle(tester);
    expect(find.text('The invoice is available after delivery'), findsOneWidget);
  });

  test('invoiceNumber is short and stable', () async {
    await seed('k1', 'delivered');
    expect(invoiceNumber(Booking.fromDoc(await db.collection('bookings').doc('k1').get())), 'LG-K1');
  });
}
