import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/customer/my_loads_view.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'customer1';
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<String> post() => LoadService.post(
        pickup: 'Delhi',
        drop: 'Mumbai',
        cargoType: 'FMCG',
        weight: 8,
        vehicleType: '20ft',
        budget: 25000,
        pickupDate: DateTime(2026, 10, 5),
        notes: '',
      );

  Future<void> acceptAs(String driver, String loadId) async {
    uid = driver;
    await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    await BookingService.accept(loadId: loadId, vehicle: (await VehicleService.fetchMyActive()).single);
    uid = 'customer1';
  }

  test('shipper cancels an open load; it leaves the open list', () async {
    final id = await post();
    await LoadService.cancel(id);
    final d = (await db.collection('loads').doc(id).get()).data()!;
    expect(d['status'], LoadStatus.closed);
    expect(d['cancelled'], isTrue);
    uid = 'driver1';
    expect(await LoadService.watchOpen().first, isEmpty);
  });

  test('matched loads and other users\' loads cannot be cancelled', () async {
    final id = await post();
    uid = 'customer2';
    expect(() => LoadService.cancel(id), throwsStateError);
    await acceptAs('driver1', id);
    expect(() => LoadService.cancel(id), throwsA(isA<LoadNotCancellableException>()));
    expect((await db.collection('loads').doc(id).get())['status'], LoadStatus.matched);
  });

  testWidgets('My Loads: cancel open load; matched load shows contact support', (tester) async {
    late String openId;
    await tester.runAsync(() async {
      openId = await post();
      final matchedId = await post();
      await acceptAs('driver1', matchedId);
    });

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MyLoadsView(onPostLoad: () {}, onOpenBooking: (_) {}))));
    await settle(tester);
    expect(find.text('Cancel load'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text('View booking'), findsOneWidget);

    await tester.tap(find.text('Cancel load'));
    await tester.pumpAndSettle();
    // Dialog says plainly that nothing is charged (MASTER-5 Task 32).
    expect(find.byKey(const ValueKey('cancelLoadFreeNote')), findsOneWidget);
    // Dialog: dismiss first, nothing changes.
    await tester.tap(find.text('Keep load'));
    await tester.pumpAndSettle();
    expect((await db.collection('loads').doc(openId).get())['status'], LoadStatus.open);

    await tester.tap(find.text('Cancel load'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await settle(tester);
    expect((await db.collection('loads').doc(openId).get())['cancelled'], isTrue);
    expect(find.text('Load cancelled'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Cancel load'), findsNothing);
  });
}
