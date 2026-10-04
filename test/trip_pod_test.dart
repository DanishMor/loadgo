import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/documents/lr_screen.dart';
import 'package:transport_app/core/documents/pod_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/trip_otp_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/customer/trip_otp_card.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });

  Future<String> booking() async {
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null,
        pickupDate: DateTime(2026, 10, 5), notes: '', extraDrops: ['Ajmer']);
    uid = 'driver1';
    await db.collection('users').doc('driver1').set({'driverName': 'Ramesh'});
    final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC1');
    final v = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == vid);
    return BookingService.accept(loadId: loadId, vehicle: v);
  }

  Future<Booking> read(String id) async => Booking.fromDoc(await db.collection('bookings').doc(id).get());

  test('customer OTPs: six digits, created once and stable', () async {
    final id = await booking();
    uid = 'customer1';
    final a = await TripOtpService.ensure(id);
    final b = await TripOtpService.ensure(id);
    expect(a.pickupOtp, matches(RegExp(r'^\d{6}$')));
    expect(a.deliveryOtp, matches(RegExp(r'^\d{6}$')));
    expect(b.pickupOtp, a.pickupOtp);
    expect(b.deliveryOtp, a.deliveryOtp);
    for (var i = 0; i < 50; i++) {
      expect(TripOtpService.newOtp(), matches(RegExp(r'^[1-9]\d{5}$')));
    }
  });

  test('pickup and delivery proofs are stored with the OTP marks', () async {
    final id = await booking();
    await advanceTo(id, BookingStatus.loading);
    await BookingService.advance(id,
        otp: '482913', pickup: const PickupProof(packages: 40, weightTons: 7.5, sealNumber: ' SL-9 ', damageNote: 'one carton torn'));
    var b = await read(id);
    expect(b.pickupOtpVerified, isTrue);
    expect(b.deliveryOtpVerified, isFalse);
    expect(b.pickupProof!.packages, 40);
    expect(b.pickupProof!.sealNumber, 'SL-9');
    await advanceTo(id, BookingStatus.unloading);
    await BookingService.advance(id, otp: '771204', delivery: const DeliveryProof(receiverName: 'Anil', receiverPhone: '+919811111111'));
    b = await read(id);
    expect(b.deliveryOtpVerified, isTrue);
    expect(b.deliveryProof!.receiverName, 'Anil');
    expect(b.timeline.keys, containsAll(BookingStatus.flow));
  });

  test('driver can cancel while arriving, not once loading', () async {
    final id = await booking();
    await BookingService.advance(id);
    expect((await read(id)).canDriverCancel, isTrue);
    await BookingService.advance(id);
    expect((await read(id)).canDriverCancel, isFalse);
  });

  test('e-way bill: 12 digits or empty', () async {
    final id = await booking();
    await BookingService.setEwayBill(id, '1234 5678 9012');
    expect((await read(id)).ewayBillNo, '123456789012');
    expect(() => BookingService.setEwayBill(id, 'EWB12'), throwsArgumentError);
    await BookingService.setEwayBill(id, '');
    expect((await read(id)).ewayBillNo, '');
  });

  Widget app(Widget home) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: home));

  testWidgets('customer OTP card shows the pickup code first, then only delivery', (tester) async {
    final id = (await tester.runAsync(booking))!;
    uid = 'customer1';
    var b = (await tester.runAsync(() => read(id)))!;
    await tester.pumpWidget(app(Scaffold(body: TripOtpCard(booking: b))));
    await settle(tester);
    expect(find.text('Pickup OTP'), findsOneWidget);
    expect(find.text('Delivery OTP'), findsOneWidget);
    final otps = (await tester.runAsync(() => TripOtpService.ensure(id)))!;
    expect(find.text(otps.pickupOtp), findsOneWidget);

    uid = 'driver1';
    await tester.runAsync(() => advanceTo(id, BookingStatus.inTransit));
    uid = 'customer1';
    b = (await tester.runAsync(() => read(id)))!;
    await tester.pumpWidget(app(Scaffold(body: TripOtpCard(key: UniqueKey(), booking: b))));
    await settle(tester);
    expect(find.text('Pickup OTP'), findsNothing);
    expect(find.text(otps.deliveryOtp), findsOneWidget);
  });

  testWidgets('LR shows booking details and saves the e-way bill; POD lists proofs', (tester) async {
    final id = (await tester.runAsync(booking))!;
    await tester.runAsync(() => advanceTo(id, BookingStatus.delivered));
    final b = (await tester.runAsync(() => read(id)))!;

    await tester.pumpWidget(app(LrScreen(bookingId: id)));
    await settle(tester);
    expect(find.text(b.lrNumber), findsOneWidget);
    expect(find.text('Delhi → Ajmer → Jaipur'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('ewayField')), '123456789012');
    await tester.tap(find.byKey(const ValueKey('ewaySave')));
    await settle(tester);
    expect((await tester.runAsync(() => read(id)))!.ewayBillNo, '123456789012');

    await tester.pumpWidget(app(PodScreen(booking: b)));
    await settle(tester);
    expect(find.text('OTP verified'), findsNWidgets(2));
    expect(find.text('Anil'), findsOneWidget);
    expect(find.text('Photos: coming later'), findsOneWidget);
  });
}
