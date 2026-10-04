import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/documents/documents_center_screen.dart';
import 'package:transport_app/core/documents/payment_card.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/pricing/gst.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/payment_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/driver/wallet_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });

  Future<String> delivered({String mode = PaymentMode.upiDirect}) async {
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 18000,
        pickupDate: DateTime(2026, 10, 5), notes: '', paymentMode: mode);
    uid = 'driver1';
    final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC1');
    final v = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == vid);
    final id = await BookingService.accept(loadId: loadId, vehicle: v);
    await advanceTo(id, BookingStatus.delivered);
    return id;
  }

  Future<Booking> read(String id) async => Booking.fromDoc(await db.collection('bookings').doc(id).get());

  test('GST split of an inclusive amount', () {
    final g = GstSplit.inclusive(2500000, 5);
    expect(g.taxable, 2380952);
    expect(g.gst, 119048);
    expect(g.cgst + g.sgst, g.gst);
    expect(g.taxable + g.gst, 2500000);
    expect(GstSplit.inclusive(105, 5).taxable, 100);
  });

  test('mark paid -> confirm received writes earning and commission', () async {
    final id = await delivered();
    var b = await read(id);
    expect(b.paymentMode, PaymentMode.upiDirect);
    expect(b.paymentStatus, PaymentStatus.pending);
    expect(b.billAmountPaise, 1800000, reason: 'budget in rupees becomes paise');

    uid = 'driver1';
    await expectLater(PaymentService.confirmReceived(b), throwsStateError, reason: 'customer has not marked paid');
    uid = 'customer1';
    expect(() => PaymentService.markPaid(b, 0), throwsArgumentError);
    await PaymentService.markPaid(b, 1800000);
    b = await read(id);
    expect(b.paymentStatus, PaymentStatus.customerMarkedPaid);
    expect(() => PaymentService.markPaid(b, 1), throwsStateError);

    uid = 'driver1';
    await PaymentService.confirmReceived(b);
    expect((await read(id)).paymentStatus, PaymentStatus.driverConfirmed);
    final ledger = await PaymentService.watchLedger().first;
    expect(ledger.map((e) => e.id), unorderedEquals(['${id}_trip_earning', '${id}_platform_commission']));
    final sum = WalletSummary.of(ledger);
    expect(sum.earnings, 1800000);
    expect(sum.commission, -90000);
    expect(sum.net, 1710000);
  });

  Widget app(Widget home) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: home));

  testWidgets('payment card: customer marks paid, driver confirms; wallet shows the lines', (tester) async {
    final id = (await tester.runAsync(delivered))!;
    uid = 'customer1';
    var b = (await tester.runAsync(() => read(id)))!;
    await tester.pumpWidget(app(Scaffold(body: PaymentCard(booking: b))));
    expect(find.text('Not paid yet'), findsOneWidget);
    expect(find.text('Records only. Online payments will come later.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('markPaid')));
    await tester.pumpAndSettle();
    expect(find.text('18000'), findsOneWidget, reason: 'prefilled with the bill amount');
    await tester.tap(find.byKey(const ValueKey('priceSubmit')));
    await settle(tester);

    uid = 'driver1';
    b = (await tester.runAsync(() => read(id)))!;
    await tester.pumpWidget(app(Scaffold(body: PaymentCard(key: UniqueKey(), booking: b))));
    expect(find.text('Customer marked paid'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirmReceived')));
    await settle(tester);

    await tester.pumpWidget(app(const WalletScreen()));
    await settle(tester);
    expect(find.text('₹ 18,000'), findsWidgets);
    expect(find.text('-₹ 900'), findsWidgets);
    expect(find.text('₹ 17,100'), findsNWidgets(2));
  });

  testWidgets('documents center lists invoice, LR and POD for delivered trips', (tester) async {
    final id = (await tester.runAsync(delivered))!;
    uid = 'customer1';
    await tester.pumpWidget(app(const DocumentsCenterScreen(asDriver: false)));
    await settle(tester);
    expect(find.byKey(ValueKey('invoice_$id')), findsOneWidget);
    expect(find.text('View LR'), findsOneWidget);
    expect(find.text('View POD'), findsOneWidget);
  });
}
