import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/driver/available_loads_view.dart';
import 'package:transport_app/driver/add_vehicle_screen.dart';

/// Fake Firestore futures complete on real async while a spinner keeps
/// animating, so give them real time before settling.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  }
  await tester.pumpAndSettle();
}

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'customer1';
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<String> postLoad() => LoadService.post(
        pickup: 'Delhi',
        drop: 'Mumbai',
        cargoType: 'FMCG',
        weight: 8,
        vehicleType: '20ft',
        budget: 25000,
        pickupDate: DateTime(2026, 10, 5),
        notes: '',
      );

  Future<Vehicle> addVehicleAs(String driver) async {
    uid = driver;
    await db.collection('users').doc(driver).set({'driverName': 'Ramesh', 'phone': '+919800000000'});
    await VehicleService.add(number: driver == 'driver1' ? 'MH12AB1234' : 'KA01CD5678', type: '20ft', capacity: 10, rcNumber: 'RC1');
    return (await VehicleService.fetchMyActive()).single;
  }

  test('accept creates booking, matches load and hides it from other drivers', () async {
    final loadId = await postLoad();
    final vehicle = await addVehicleAs('driver1');

    expect((await LoadService.watchOpen().first).map((l) => l.id), [loadId]);

    final bookingId = await BookingService.accept(loadId: loadId, vehicle: vehicle);
    expect(bookingId, isNot(loadId));

    final booking = (await db.collection('bookings').doc(bookingId).get()).data()!;
    expect(booking['loadId'], loadId);
    expect(booking['driverId'], 'driver1');
    expect(booking['vehicleId'], vehicle.id);
    expect(booking['customerId'], 'customer1');
    expect(booking['status'], BookingStatus.accepted);
    expect(booking['driverName'], 'Ramesh');
    expect(booking['vehicleNumber'], 'MH12AB1234');
    expect(booking['createdAt'], isNotNull);

    final load = (await db.collection('loads').doc(loadId).get()).data()!;
    expect(load['status'], LoadStatus.matched);
    expect(load['driverId'], 'driver1');
    expect(load['bookingId'], bookingId);

    // Another driver no longer sees it and cannot accept it.
    final other = await addVehicleAs('driver2');
    expect(await LoadService.watchOpen().first, isEmpty);
    expect(() => BookingService.accept(loadId: loadId, vehicle: other), throwsA(isA<LoadUnavailableException>()));

    // Customer sees the status change and the booking.
    uid = 'customer1';
    expect((await LoadService.watchMine().first).single.status, LoadStatus.matched);
    expect((await BookingService.watchForCustomer().first).single.id, bookingId);
  });

  test('a user cannot accept their own load and missing loads are unavailable', () async {
    final loadId = await postLoad();
    final vehicle = await addVehicleAs('customer1');
    expect(await LoadService.watchOpen().first, isEmpty, reason: 'own loads are hidden');
    expect(() => BookingService.accept(loadId: loadId, vehicle: vehicle), throwsA(isA<LoadUnavailableException>()));
    expect(() => BookingService.accept(loadId: 'nope', vehicle: vehicle), throwsA(isA<LoadUnavailableException>()));
  });

  testWidgets('driver accepts a load from the list via the vehicle sheet', (tester) async {
    await tester.runAsync(() async {
      await postLoad();
      await addVehicleAs('driver1');
    });

    String? accepted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AvailableLoadsView(loads: LoadService.watchOpenPage, onAccepted: (id) => accepted = id)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Delhi → Mumbai'), findsOneWidget);
    expect(find.text('₹ 25000'), findsOneWidget);

    await tester.tap(find.byType(AcceptLoadButton));
    await settle(tester);
    expect(find.text('Choose vehicle'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(ListTile), matching: find.text('Accept')));
    await settle(tester);

    expect(accepted, isNotNull);
    expect(find.text('Load accepted'), findsOneWidget);
    expect(find.text('No open loads right now'), findsOneWidget);
  });

  testWidgets('driver without a vehicle is sent to Add Vehicle', (tester) async {
    await tester.runAsync(postLoad);
    uid = 'driver1';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AvailableLoadsView(loads: LoadService.watchOpenPage)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AcceptLoadButton));
    await settle(tester);

    expect(find.byType(AddVehicleScreen), findsOneWidget);
    expect((await db.collection('bookings').get()).docs, isEmpty);
  });
}
