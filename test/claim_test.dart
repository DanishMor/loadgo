import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_claims_screen.dart';
import 'package:transport_app/core/claims/claim_screens.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/claim.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/claim_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/widgets/common.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<Booking> booking(String target) async {
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000,
        pickupDate: DateTime(2026, 10, 5), notes: '');
    uid = 'driver1';
    final vid = await VehicleService.add(number: 'MH12AB1000', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).firstWhere((v) => v.id == vid);
    final id = await BookingService.accept(loadId: loadId, vehicle: vehicle);
    await advanceTo(id, target);
    return Booking.fromDoc(await db.collection('bookings').doc(id).get());
  }

  test('a claim needs a trip that reached unloading, a real text, and is one per party', () async {
    final early = await booking(BookingStatus.inTransit);
    uid = 'customer1';
    await expectLater(ClaimService.open(booking: early, type: ClaimType.damage, description: 'Boxes were crushed'), throwsA(isA<ClaimException>().having((e) => e.reason, 'r', 'not_ready')));
    uid = 'driver1';
    await advanceTo(early.id, BookingStatus.delivered);
    uid = 'customer1';
    final b = Booking.fromDoc(await db.collection('bookings').doc(early.id).get());
    await expectLater(ClaimService.open(booking: b, type: ClaimType.damage, description: 'short'), throwsA(isA<ClaimException>().having((e) => e.reason, 'r', 'description')));
    await expectLater(ClaimService.open(booking: b, type: ClaimType.damage, description: 'Boxes were crushed', amountPaise: 99999999), throwsA(isA<ClaimException>()));
    final id = await ClaimService.open(booking: b, type: ClaimType.damage, description: 'Boxes were crushed', amountPaise: 500000);
    expect(id, '${b.id}_customer1');
    await expectLater(ClaimService.open(booking: b, type: ClaimType.delay, description: 'Another claim text'), throwsA(isA<ClaimException>().having((e) => e.reason, 'r', 'already')));
    uid = 'driver2';
    await expectLater(ClaimService.open(booking: b, type: ClaimType.delay, description: 'Not my trip at all'), throwsStateError);
    uid = 'driver1';
    final driverClaim = await ClaimService.open(booking: b, type: ClaimType.payment, description: 'Customer has not paid');
    expect(driverClaim, '${b.id}_driver1');
    expect((await ClaimService.watchForBooking(b.id).first).length, 2);
  });

  test('both parties see the claim and its timeline; admin reviews and resolves; closed claims take no party messages', () async {
    final b = await booking(BookingStatus.delivered);
    uid = 'customer1';
    final id = await ClaimService.open(booking: b, type: ClaimType.shortage, description: 'Two cartons are missing', amountPaise: 120000);
    var claim = (await ClaimService.watch(id).first)!;
    uid = 'driver1';
    expect((await ClaimService.watchMine().first).single.id, id);
    await ClaimService.addMessage(claim, 'I delivered all 40 cartons');
    uid = 'admin1';
    await ClaimService.startReview(claim);
    claim = (await ClaimService.watch(id).first)!;
    expect(claim.status, ClaimStatus.underReview);
    await ClaimService.addMessage(claim, 'Please send photos by chat', admin: true);
    await ClaimService.resolve(claim, outcome: ClaimOutcome.partial, note: 'One carton', awardedPaise: 60000);
    claim = (await ClaimService.watch(id).first)!;
    expect((claim.status, claim.outcome, claim.awardedPaise, claim.resolutionNote), ('resolved', 'partial', 60000, 'One carton'));
    final events = await ClaimService.watchEvents(id).first;
    expect(events.map((e) => (e.role, e.kind)), [('customer', 'opened'), ('driver', 'message'), ('admin', 'status'), ('admin', 'message'), ('admin', 'resolution')]);
    uid = 'customer1';
    await expectLater(ClaimService.addMessage(claim, 'one more thing'), throwsA(isA<ClaimException>()));
    expect((await ClaimService.watchMine().first).single.outcome, 'partial');
  });

  testWidgets('screens: report from the card, then admin resolves in the UI', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Booking b;
    await tester.runAsync(() async => b = await booking(BookingStatus.delivered));
    uid = 'customer1';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ClaimCard(booking: b)))));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('reportProblem')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('claimText')), 'The pallets were wet on arrival');
    await tester.tap(find.byType(PrimaryButton));
    await settle(tester);
    expect((await db.collection('claims').get()).docs.single['description'], 'The pallets were wet on arrival');
    expect(find.text('Open'), findsOneWidget);

    uid = 'admin1';
    await tester.pumpWidget(const MaterialApp(home: AdminClaimsScreen()));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('adminClaim_${b.id}_customer1')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('claimResolve')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('claimResolveOk')));
    await settle(tester);
    expect((await db.collection('claims').get()).docs.single['status'], 'resolved');
    expect(find.textContaining('Upheld'), findsWidgets);
  });
}
