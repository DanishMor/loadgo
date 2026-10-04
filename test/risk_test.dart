import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/flagged_users_screen.dart';
import 'package:transport_app/core/models/risk.dart';
import 'package:transport_app/core/services/admin_service.dart';
import 'package:transport_app/core/services/audit_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/risk_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<String> postLoad() => LoadService.post(
      pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000,
      pickupDate: DateTime(2026, 10, 5), notes: '');

  Future<List<String>> auditTypes() async =>
      (await db.collection('audit_events').get()).docs.map((d) => d['type'] as String).toList();

  test('tier helper: only normal/review can transact', () {
    expect(RiskTier.canTransact(null), isTrue);
    expect(RiskTier.canTransact(RiskTier.review), isTrue);
    expect(RiskTier.canTransact(RiskTier.restricted), isFalse);
    expect(RiskTier.canTransact(RiskTier.suspended), isFalse);
  });

  test('restricted users cannot post, offer or accept', () async {
    uid = 'customer1';
    final loadId = await postLoad();
    await db.collection('users').doc('customer1').set({'riskTier': RiskTier.restricted});
    expect(postLoad(), throwsA(isA<AccountRestrictedException>()));

    uid = 'driver1';
    await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).first;
    await db.collection('users').doc('driver1').set({'riskTier': RiskTier.suspended});
    expect(BookingService.accept(loadId: loadId, vehicle: vehicle), throwsA(isA<AccountRestrictedException>()));
    final load = (await LoadService.watchOpen().first).first;
    expect(OfferService.send(load: load, vehicle: vehicle, pricePaise: 100000), throwsA(isA<AccountRestrictedException>()));

    await db.collection('users').doc('driver1').set({'riskTier': RiskTier.review});
    await BookingService.accept(loadId: loadId, vehicle: vehicle);
  });

  test('accept, status change and cancel write audit events; cancels are counted', () async {
    uid = 'customer1';
    final loadId = await postLoad();
    uid = 'driver1';
    await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).first;
    final bookingId = await BookingService.accept(loadId: loadId, vehicle: vehicle);
    await BookingService.advance(bookingId);
    await BookingService.cancelByDriver(bookingId);
    expect(await auditTypes(), unorderedEquals([AuditType.accept, AuditType.statusChange, AuditType.cancel]));
    expect((await db.collection('users').doc('driver1').get())['cancelCount'], 1);

    uid = 'customer1';
    await LoadService.cancel(loadId);
    expect((await db.collection('users').doc('customer1').get())['cancelCount'], 1);
    expect(await auditTypes(), contains(AuditType.cancel));
  });

  test('admin verification and risk change are audited; flagged list ranks users', () async {
    uid = 'admin1';
    await db.collection('users').doc('d1').set({'driverName': 'Ramesh', 'verificationStatus': 'pending', 'verified': false});
    await db.collection('users').doc('d2').set({'driverName': 'Suresh', 'cancelCount': 4});
    await db.collection('users').doc('d3').set({'driverName': 'Fine', 'cancelCount': 1});
    await db.collection('users').doc('c1').set({'name': 'Cust'});
    await db.collection('reports').add({'reportedId': 'c1', 'status': 'open', 'reporterId': 'd1'});
    await db.collection('reports').add({'reportedId': 'd3', 'status': 'resolved', 'reporterId': 'd1'});
    await AdminService.setStatus('d1', AdminService.approved);
    await RiskService.setTier('d1', RiskTier.restricted, reason: 'fraud');

    final flagged = await RiskService.flagged();
    expect(flagged.map((u) => u.uid), ['d1', 'c1', 'd2']);
    expect(flagged.first.riskTier, RiskTier.restricted);
    expect(flagged[1].openReports, 1);
    expect(flagged.last.cancelCount, 4);
    expect(await auditTypes(), unorderedEquals([AuditType.verification, AuditType.riskChange]));
    expect(() => RiskService.setTier('d1', 'bogus'), throwsArgumentError);
  });

  testWidgets('flagged users screen lists users and edits the tier', (tester) async {
    uid = 'admin1';
    await db.collection('users').doc('d2').set({'driverName': 'Suresh', 'cancelCount': 4});
    await tester.pumpWidget(const MaterialApp(home: FlaggedUsersScreen()));
    await settle(tester);
    expect(find.text('Suresh'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('flagged_d2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tier_suspended')));
    await tester.tap(find.byKey(const ValueKey('saveTier')));
    await settle(tester);
    expect((await db.collection('users').doc('d2').get())['riskTier'], RiskTier.suspended);
  });
}
