import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/documents/eway_status_line.dart';
import 'package:transport_app/core/documents/payment_card.dart';
import 'package:transport_app/core/enterprise/handover_card.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/payments/payment_logic.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/handover_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/payment_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });

  Future<Booking> read(String id) async => Booking.fromDoc(await db.collection('bookings').doc(id).get());

  /// A booking by customer1 for driver [driver] (a new vehicle each time).
  Future<String> booked({String driver = 'driver1', String? shipmentId, int? leg, String vehicleNo = 'MH12AB1234', num budget = 18000}) async {
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: budget,
        pickupDate: DateTime(2026, 10, 5), notes: '', shipmentId: shipmentId, shipmentLeg: leg);
    uid = driver;
    final vid = await VehicleService.add(number: vehicleNo, type: '14ft', capacity: 4, rcNumber: 'RC$vehicleNo');
    final v = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == vid);
    return BookingService.accept(loadId: loadId, vehicle: v);
  }

  Widget app(Widget home) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: home));

  group('UPI link (P0-06, PAY1)', () {
    test('upi://pay with payee, rupees with two decimals, INR, note and reference', () {
      final u = upiPayUri(upiId: ' ravi.k@okaxis ', payeeName: 'Ravi Kumar', amountPaise: 1250050, note: 'Delhi to Jaipur', ref: 'B1');
      expect(u.scheme, 'upi');
      expect(u.host, 'pay');
      expect(u.queryParameters, {'pa': 'ravi.k@okaxis', 'pn': 'Ravi Kumar', 'am': '12500.50', 'cu': 'INR', 'tn': 'Delhi to Jaipur', 'tr': 'B1'});
      expect(upiPayUri(upiId: 'a@b', payeeName: '', amountPaise: 5, note: 'x' * 60, ref: 'r').queryParameters['am'], '0.05');
      expect(upiPayUri(upiId: 'a@b', payeeName: '', amountPaise: 5, note: 'x' * 60, ref: 'r').queryParameters['tn']!.length, 40);
    });

    test('the driver shares the payout UPI id on the booking; nothing without a valid one', () async {
      final id = await booked();
      var b = await read(id);
      expect(await PaymentService.shareUpiId(b), isFalse);
      await db.collection('users').doc('driver1').set({'payoutProfile': {'upiId': 'ravi@okaxis', 'holder': 'Ravi'}});
      expect(await PaymentService.shareUpiId(b), isTrue);
      b = await read(id);
      expect(b.payUpiId, 'ravi@okaxis');
      uid = 'customer1';
      await expectLater(PaymentService.shareUpiId(b), throwsStateError);
    });

    testWidgets('card shows Pay by UPI to the customer and Share UPI id to the driver', (tester) async {
      final id = (await tester.runAsync(() => booked()))!;
      var b = (await tester.runAsync(() => read(id)))!;
      uid = 'driver1';
      await tester.pumpWidget(app(Scaffold(body: PaymentCard(booking: b))));
      expect(find.byKey(const ValueKey('shareUpi')), findsOneWidget);
      expect(find.byKey(const ValueKey('payViaUpi')), findsNothing);
      b = Booking.fromMap(id, {...(await tester.runAsync(() => db.collection('bookings').doc(id).get()))!.data()!, 'payUpiId': 'ravi@okaxis'});
      uid = 'customer1';
      await tester.pumpWidget(app(Scaffold(body: PaymentCard(key: UniqueKey(), booking: b))));
      expect(find.byKey(const ValueKey('payViaUpi')), findsOneWidget);
      expect(find.byKey(const ValueKey('shareUpi')), findsNothing);
    });
  });

  group('advance payment (PAY3)', () {
    test('rules of an advance: at least Re 1, below the fare', () {
      expect(validAdvance(100, 1800000), isTrue);
      expect(validAdvance(99, 1800000), isFalse);
      expect(validAdvance(1800000, 1800000), isFalse);
      expect(validAdvance(500000, null), isTrue);
      expect(const AdvanceSummary(advancePaise: 500000, totalPaise: 1800000, confirmed: true).balancePaise, 1300000);
    });

    test('customer records once, driver confirms once; the final payment stays the total', () async {
      final id = await booked();
      var b = await read(id);
      uid = 'customer1';
      await expectLater(() => PaymentService.recordAdvance(b, 50), throwsArgumentError);
      await expectLater(() => PaymentService.recordAdvance(b, 1800000), throwsArgumentError, reason: 'not below the fare');
      await PaymentService.recordAdvance(b, 500000);
      b = await read(id);
      expect(b.advancePaise, 500000);
      expect(b.advanceConfirmedAt, isNull);
      await expectLater(() => PaymentService.recordAdvance(b, 100000), throwsStateError, reason: 'second advance');
      uid = 'customer1';
      await expectLater(() => PaymentService.confirmAdvance(b), throwsStateError, reason: 'only the driver');
      uid = 'driver1';
      await PaymentService.confirmAdvance(b);
      b = await read(id);
      expect(b.advanceConfirmedAt, isNotNull);
      await expectLater(() => PaymentService.confirmAdvance(b), throwsStateError, reason: 'double confirm');
      expect(b.billAmountPaise, 1800000);
      uid = 'customer1';
      await PaymentService.markPaid(b, 1800000);
      uid = 'driver1';
      await PaymentService.confirmReceived(await read(id));
      expect((await db.collection('ledger').get()).docs.length, 2);
    });

    testWidgets('card: customer records an advance, driver confirms it', (tester) async {
      final id = (await tester.runAsync(() => booked()))!;
      uid = 'customer1';
      var b = (await tester.runAsync(() => read(id)))!;
      await tester.pumpWidget(app(Scaffold(body: PaymentCard(booking: b))));
      await tester.tap(find.byKey(const ValueKey('recordAdvance')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '5000');
      await tester.tap(find.byKey(const ValueKey('priceSubmit')));
      await settle(tester);
      b = (await tester.runAsync(() => read(id)))!;
      expect(b.advancePaise, 500000);
      uid = 'driver1';
      await tester.pumpWidget(app(Scaffold(body: PaymentCard(key: UniqueKey(), booking: b))));
      expect(find.byKey(const ValueKey('advanceLine')), findsOneWidget);
      expect(find.textContaining('balance'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirmAdvance')));
      await settle(tester);
      b = (await tester.runAsync(() => read(id)))!;
      expect(b.advanceConfirmedAt, isNotNull);
    });
  });

  group('e-way bill validity (DOC4)', () {
    final now = DateTime(2026, 10, 6, 12);
    test('states: missing, no date, valid, expiring (soon or before the delivery), expired', () {
      expect(ewayStatus(number: '', validUntil: now, now: now).state, EwayState.missing);
      expect(ewayStatus(number: '123456789012', validUntil: null, now: now).state, EwayState.noDate);
      expect(ewayStatus(number: '123456789012', validUntil: now.add(const Duration(days: 2)), now: now).state, EwayState.valid);
      expect(ewayStatus(number: '123456789012', validUntil: now.add(const Duration(hours: 5)), now: now).state, EwayState.expiring);
      expect(ewayStatus(number: '123456789012', validUntil: now.add(const Duration(days: 2)), now: now, expectedDelivery: now.add(const Duration(days: 3))).state, EwayState.expiring);
      expect(ewayStatus(number: '123456789012', validUntil: now.subtract(const Duration(minutes: 1)), now: now).state, EwayState.expired);
    });

    test('setEwayBill stores the validity; a date over a year ahead and a bad number are refused; clearing removes both', () async {
      final id = await booked();
      uid = 'customer1';
      await BookingService.setEwayBill(id, '1234 5678 9012', validUntil: DateTime(2026, 10, 8, 23, 59), now: DateTime(2026, 10, 6));
      var b = await read(id);
      expect(b.ewayBillNo, '123456789012');
      expect(b.ewayValidUntil, DateTime(2026, 10, 8, 23, 59));
      expect(() => BookingService.setEwayBill(id, '123456789012', validUntil: DateTime(2028), now: DateTime(2026, 10, 6)), throwsArgumentError);
      expect(() => BookingService.setEwayBill(id, '123'), throwsArgumentError);
      await BookingService.setEwayBill(id, '');
      b = await read(id);
      expect((b.ewayBillNo, b.ewayValidUntil), ('', null));
    });

    testWidgets('the line warns about no date, expiring and expired bills and says nothing without a bill', (tester) async {
      final id = (await tester.runAsync(() => booked()))!;
      final base = (await tester.runAsync(() => db.collection('bookings').doc(id).get()))!.data()!;
      Future<void> show(Map<String, Object?> extra) async {
        await tester.pumpWidget(app(Scaffold(body: EwayStatusLine(key: UniqueKey(), booking: Booking.fromMap(id, {...base, ...extra}), now: () => DateTime(2026, 10, 6, 12)))));
      }
      await show({});
      expect(find.byType(Text), findsNothing);
      await show({'ewayBillNo': '123456789012'});
      expect(find.byKey(const ValueKey('eway_noDate')), findsOneWidget);
      await show({'ewayBillNo': '123456789012', 'ewayValidUntil': Timestamp.fromDate(DateTime(2026, 10, 6, 17))});
      expect(find.text('E-way bill expires in 5 h.'), findsOneWidget);
      await show({'ewayBillNo': '123456789012', 'ewayValidUntil': Timestamp.fromDate(DateTime(2026, 10, 5))});
      expect(find.byKey(const ValueKey('eway_expired')), findsOneWidget);
      await show({'ewayBillNo': '123456789012', 'ewayValidUntil': Timestamp.fromDate(DateTime(2026, 10, 9))});
      expect(find.byKey(const ValueKey('eway_valid')), findsOneWidget);
    });
  });

  group('container handover (IE10)', () {
    Future<(String, String)> twoLegs() async {
      final a = await booked(driver: 'driver1', shipmentId: 'S1', leg: 1);
      final b = await booked(driver: 'driver2', shipmentId: 'S1', leg: 2, vehicleNo: 'GJ01CD5678');
      return (a, b);
    }

    test('leg of a booking comes from its load; an ordinary booking has none', () async {
      final (a, b) = await twoLegs();
      expect((await HandoverService.legOf(await read(a)))!.leg, 1);
      expect((await HandoverService.legOf(await read(b)))!.shipmentId, 'S1');
      final plain = await booked(driver: 'driver3', vehicleNo: 'KA01EF0001');
      expect(await HandoverService.legOf(await read(plain)), isNull);
    });

    test('leg 1 hands over from unloading; leg 2 confirms; a different seal is flagged; each side once', () async {
      final (a, b) = await twoLegs();
      final l1 = (await HandoverService.legOf(await read(a)))!;
      final l2 = (await HandoverService.legOf(await read(b)))!;
      uid = 'driver1';
      await expectLater(HandoverService.handOver(await read(a), l1), throwsA(isA<HandoverException>().having((e) => e.reason, 'r', 'status')));
      await advanceTo(a, BookingStatus.unloading);
      await expectLater(HandoverService.handOver(await read(a), l1, container: 'BAD'), throwsA(isA<HandoverException>().having((e) => e.reason, 'r', 'container')));
      await expectLater(HandoverService.handOver(await read(a), l1, seal: 'no spaces!'), throwsA(isA<HandoverException>().having((e) => e.reason, 'r', 'seal')));
      await expectLater(HandoverService.handOver(await read(a), l2), throwsA(isA<HandoverException>().having((e) => e.reason, 'r', 'leg')));
      uid = 'driver2';
      await expectLater(HandoverService.receive(await read(b), l2), throwsA(isA<HandoverException>().having((e) => e.reason, 'r', 'waiting')));
      uid = 'driver1';
      await HandoverService.handOver(await read(a), l1, container: 'csqu 3054383', seal: 'SL-9', note: 'door sealed');
      await expectLater(HandoverService.handOver(await read(a), l1), throwsA(isA<HandoverException>().having((e) => e.reason, 'r', 'already')));
      uid = 'driver2';
      expect(await HandoverService.receive(await read(b), l2, seal: 'SL-9'), isTrue);
      await expectLater(HandoverService.receive(await read(b), l2, seal: 'SL-9'), throwsA(isA<HandoverException>().having((e) => e.reason, 'r', 'already')));
      final h = (await HandoverService.watch('S1').first)!;
      expect(h.complete, isTrue);
      expect(h.sealMatches, isTrue);
      expect(h.containerNumber, 'CSQU3054383');
      expect(h.leg2!.driverId, 'driver2');
    });

    test('a different seal at leg 2 is recorded as not matching', () async {
      final (a, b) = await twoLegs();
      uid = 'driver1';
      await advanceTo(a, BookingStatus.unloading);
      await HandoverService.handOver(await read(a), (await HandoverService.legOf(await read(a)))!, seal: 'SL-9');
      uid = 'driver2';
      expect(await HandoverService.receive(await read(b), (await HandoverService.legOf(await read(b)))!, seal: 'SL-1'), isFalse);
      expect((await HandoverService.watch('S1').first)!.sealMatches, isFalse);
    });

    testWidgets('card: leg 2 waits, leg 1 hands over, leg 2 confirms, both see the result', (tester) async {
      final (a, b) = (await tester.runAsync(twoLegs))!;
      uid = 'driver1';
      await tester.runAsync(() => advanceTo(a, BookingStatus.unloading));
      var bk2 = (await tester.runAsync(() => read(b)))!;
      uid = 'driver2';
      await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: HandoverCard(booking: bk2)))));
      await settle(tester);
      expect(find.byKey(const ValueKey('hoWaiting')), findsOneWidget);
      final bk1 = (await tester.runAsync(() => read(a)))!;
      uid = 'driver1';
      await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: HandoverCard(key: UniqueKey(), booking: bk1)))));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('hoSeal')), 'sl-9');
      await tester.tap(find.byKey(const ValueKey('hoHandOver')));
      await settle(tester);
      expect(find.byKey(const ValueKey('hoLeg1Done')), findsOneWidget);
      uid = 'driver2';
      bk2 = (await tester.runAsync(() => read(b)))!;
      await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: HandoverCard(key: UniqueKey(), booking: bk2)))));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('hoSeal')), 'sl-9');
      await tester.tap(find.byKey(const ValueKey('hoReceive')));
      await settle(tester);
      expect(find.byKey(const ValueKey('hoDone')), findsOneWidget);
    });
  });

  group('duplicates and double confirms (TEST6)', () {
    test('mark paid twice, confirm twice and confirm before paying all fail and leave two ledger lines', () async {
      final id = await booked();
      await advanceTo(id, BookingStatus.delivered);
      var b = await read(id);
      uid = 'driver1';
      await expectLater(() => PaymentService.confirmReceived(b), throwsStateError);
      uid = 'customer1';
      await PaymentService.markPaid(b, 1800000);
      await expectLater(() async => PaymentService.markPaid(await read(id), 1800000), throwsStateError, reason: 'second mark');
      uid = 'driver1';
      b = await read(id);
      await PaymentService.confirmReceived(b);
      await expectLater(() async => PaymentService.confirmReceived(await read(id)), throwsStateError, reason: 'second confirm');
      uid = 'driver2';
      await expectLater(() async => PaymentService.confirmReceived(await read(id)), throwsStateError, reason: 'someone else');
      final ledger = await db.collection('ledger').get();
      expect(ledger.docs.map((d) => d.id), unorderedEquals(['${id}_trip_earning', '${id}_platform_commission']));
      expect((await read(id)).paidAmountPaise, 1800000);
    });

    test('an amount outside 1 paise .. Rs 10 lakh is refused', () async {
      final id = await booked();
      uid = 'customer1';
      final b = await read(id);
      await expectLater(() => PaymentService.markPaid(b, -5), throwsArgumentError);
      await expectLater(() => PaymentService.markPaid(b, 100000001), throwsArgumentError);
    });
  });
}
