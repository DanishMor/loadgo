import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/location_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/features/bookings/booking_tracking_screen.dart';
import 'package:transport_app/features/bookings/driver_trip_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
  });
  tearDown(() => LocationService.useFake(null));

  Future<String> bookingAt(String status) async {
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000,
        pickupDate: DateTime(2026, 10, 5), notes: '');
    uid = 'driver1';
    await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final id = await BookingService.accept(loadId: loadId, vehicle: (await VehicleService.fetchMyActive()).first);
    while ((await db.collection('bookings').doc(id).get())['status'] != status) {
      await BookingService.advance(id);
    }
    return id;
  }

  test('location is stored only for the assigned driver while in transit', () async {
    final id = await bookingAt('picked_up');
    await BookingService.updateLocation(id, 28.6, 77.2);
    expect((await db.collection('bookings').doc(id).get()).data()!.containsKey('lastKnownLocation'), isFalse);

    await BookingService.advance(id);
    uid = 'driver2';
    await BookingService.updateLocation(id, 1, 1);
    expect((await db.collection('bookings').doc(id).get()).data()!.containsKey('lastKnownLocation'), isFalse);

    uid = 'driver1';
    await BookingService.updateLocation(id, 28.6, 77.2);
    final b = Booking.fromDoc(await db.collection('bookings').doc(id).get());
    expect(b.lastKnownLocation, const GeoPoint(28.6, 77.2));
    expect(b.locationUpdatedAt, isNotNull);
  });

  testWidgets('driver screen publishes positions (throttled) and customer sees them', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final positions = StreamController<Coordinates>();
    addTearDown(positions.close);
    LocationService.useFake(() => positions.stream);
    late String id;
    await tester.runAsync(() async => id = await bookingAt('in_transit'));

    uid = 'driver1';
    await tester.pumpWidget(MaterialApp(home: DriverTripScreen(bookingId: id)));
    await settle(tester);
    expect(find.text('Sharing your live location with the customer'), findsOneWidget);

    positions.add((lat: 19.07, lng: 72.87));
    positions.add((lat: 19.5, lng: 73.0)); // within the throttle window: ignored
    await settle(tester);
    var loc = (await tester.runAsync(() => db.collection('bookings').doc(id).get()))!['lastKnownLocation'] as GeoPoint;
    expect((loc.latitude, loc.longitude), (19.07, 72.87));

    uid = 'customer1';
    await tester.pumpWidget(MaterialApp(home: BookingTrackingScreen(bookingId: id)));
    await settle(tester);
    expect(find.text('Driver location'), findsOneWidget);
    expect(find.text('19.07000, 72.87000'), findsOneWidget);
  });
}
