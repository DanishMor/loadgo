import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/documents/invoice_issue_card.dart';
import 'package:transport_app/core/documents/invoice_pdf.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/invoice.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/invoice_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  var n = 0;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<Booking> delivered({int budget = 25000}) async {
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: budget,
        pickupDate: DateTime(2026, 10, 5), notes: '');
    uid = 'driver1';
    final vid = await VehicleService.add(number: 'MH12AB${2000 + n++}', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).firstWhere((v) => v.id == vid);
    final id = await BookingService.accept(loadId: loadId, vehicle: vehicle);
    await advanceTo(id, BookingStatus.delivered);
    return Booking.fromDoc(await db.collection('bookings').doc(id).get());
  }

  test('financial year runs April to March; numbers are padded', () {
    expect(financialYear(DateTime(2026, 3, 31)), '2025-26');
    expect(financialYear(DateTime(2026, 4, 1)), '2026-27');
    expect(financialYear(DateTime(2026, 12, 31)), '2026-27');
    expect(financialYear(DateTime(2099, 6, 1)), '2099-00');
    expect(invoiceSeriesNumber('2026-27', 42), 'LG/2026-27/00042');
  });

  test('issuing numbers invoices gaplessly per driver and snapshots GST', () async {
    final a = await delivered();
    final b = await delivered();
    final fy = financialYear(DateTime.now());
    final first = await InvoiceService.issue(booking: a, sellerName: ' Ramesh Transport ', sellerGstin: '27abcde1234f1z5', ewayBillNo: '123456789012', ewayDistanceKm: 1400);
    final second = await InvoiceService.issue(booking: b, sellerName: 'Ramesh Transport', buyerName: 'Acme');
    expect((first.number, second.number), ('LG/$fy/00001', 'LG/$fy/00002'));
    final saved = (await db.collection('invoices').doc(a.id).get()).data()!;
    expect((saved['sellerName'], saved['sellerGstin'], saved['ewayBillNo'], saved['ewayDistanceKm']), ('Ramesh Transport', '27ABCDE1234F1Z5', '123456789012', 1400));
    expect(saved['taxablePaise'] + saved['cgstPaise'] + saved['sgstPaise'], saved['totalPaise']);
    expect(saved['totalPaise'], 2500000);
    expect((await db.collection('invoice_series').doc('driver1_$fy').get())['next'], 3);
    await expectLater(InvoiceService.issue(booking: a, sellerName: 'x'), throwsA(isA<InvoiceException>().having((e) => e.reason, 'r', 'exists')));
    expect((await InvoiceService.watch(a.id).first)!.customerId, 'customer1');
  });

  test('only the driver of a delivered trip issues; inputs are checked', () async {
    final a = await delivered();
    uid = 'customer1';
    await expectLater(InvoiceService.issue(booking: a, sellerName: 'x'), throwsA(isA<InvoiceException>().having((e) => e.reason, 'r', 'not_driver')));
    uid = 'driver1';
    await expectLater(InvoiceService.issue(booking: a, sellerName: ' '), throwsA(isA<InvoiceException>().having((e) => e.reason, 'r', 'seller')));
    await expectLater(InvoiceService.issue(booking: a, sellerName: 'x', sellerGstin: '123'), throwsA(isA<InvoiceException>().having((e) => e.reason, 'r', 'gstin')));
    await expectLater(InvoiceService.issue(booking: a, sellerName: 'x', ewayBillNo: '12345'), throwsA(isA<InvoiceException>().having((e) => e.reason, 'r', 'eway')));
    final notDone = Booking.fromDoc(await db.collection('bookings').doc(a.id).get());
    await db.collection('bookings').doc(a.id).update({'status': 'in_transit'});
    await expectLater(InvoiceService.issue(booking: Booking.fromDoc(await db.collection('bookings').doc(a.id).get()), sellerName: 'x'),
        throwsA(isA<InvoiceException>().having((e) => e.reason, 'r', 'not_delivered')));
    expect(notDone.status, 'delivered');
  });

  test('e-way details can be added later; the PDF is a real PDF', () async {
    final a = await delivered();
    final inv = await InvoiceService.issue(booking: a, sellerName: 'Ramesh');
    await InvoiceService.saveEway(a.id, ewayBillNo: '210987654321', validUntil: DateTime(2026, 11, 1), distanceKm: 900);
    await expectLater(InvoiceService.saveEway(a.id, ewayBillNo: 'abc'), throwsA(isA<InvoiceException>()));
    final updated = (await InvoiceService.watch(a.id).first)!;
    expect((updated.ewayBillNo, updated.ewayDistanceKm, updated.ewayValidUntil), ('210987654321', 900, DateTime(2026, 11, 1)));
    expect(inv.number, updated.number);
    final bytes = await buildInvoicePdf(updated, a);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  testWidgets('card: driver issues, then both sides see the number and can share', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Booking b;
    await tester.runAsync(() async => b = await delivered());
    TripInvoice? shared;
    Widget app() => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: InvoiceIssueCard(booking: b, onShare: (i, _) async => shared = i))));

    uid = 'customer1';
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('The driver has not issued the GST invoice yet'), findsOneWidget);

    uid = 'driver1';
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('sellerName')), 'Ramesh Transport');
    await tester.enterText(find.byKey(const ValueKey('ewayNo')), '12345');
    await tester.tap(find.text('Issue invoice'));
    await settle(tester);
    expect((await db.collection('invoices').get()).docs, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('ewayNo')), '123456789012');
    await tester.tap(find.text('Issue invoice'));
    await settle(tester);
    expect(find.byKey(const ValueKey('invoiceSeriesNo')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shareInvoicePdf')));
    await tester.pump();
    expect(shared?.ewayBillNo, '123456789012');
  });
}
