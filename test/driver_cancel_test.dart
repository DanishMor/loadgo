import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/models/app_notification.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/features/bookings/driver_trip_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late String loadId;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<Vehicle> vehicleFor(String driver) async {
    uid = driver;
    await VehicleService.add(number: driver == 'driver1' ? 'MH12AB1234' : 'KA01CD5678', type: '20ft', capacity: 10, rcNumber: 'RC1');
    return (await VehicleService.fetchMyActive()).first;
  }

  Future<String> acceptedBooking() async {
    uid = 'customer1';
    loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000,
        pickupDate: DateTime(2026, 10, 5), notes: '');
    final v = await vehicleFor('driver1');
    return BookingService.accept(loadId: loadId, vehicle: v);
  }

  test('cancel reopens the load, notifies the customer, and another driver can accept', () async {
    final first = await acceptedBooking();
    await BookingService.cancelByDriver(first);

    final booking = (await db.collection('bookings').doc(first).get()).data()!;
    expect(booking['status'], BookingStatus.cancelled);
    expect((booking['timeline'] as Map).containsKey('cancelled'), isTrue);
    final load = (await db.collection('loads').doc(loadId).get()).data()!;
    expect(load['status'], LoadStatus.open);
    expect(load.containsKey('driverId'), isFalse);
    expect(load.containsKey('bookingId'), isFalse);

    final notes = (await db.collection('notifications').where('userId', isEqualTo: 'customer1').get()).docs;
    expect(notes.map((d) => d['type']), contains(NotificationType.bookingCancelled));

    final second = await BookingService.accept(loadId: loadId, vehicle: await vehicleFor('driver2'));
    expect(second, isNot(first));
    expect((await db.collection('loads').doc(loadId).get())['driverId'], 'driver2');
    uid = 'customer1';
    final customerBookings = await BookingService.watchForCustomer().first;
    expect(customerBookings.map((b) => b.status), unorderedEquals([BookingStatus.accepted, BookingStatus.cancelled]));
  });

  test('cannot cancel after pickup or as another user', () async {
    final id = await acceptedBooking();
    uid = 'driver2';
    expect(() => BookingService.cancelByDriver(id), throwsStateError);
    uid = 'driver1';
    await BookingService.advance(id);
    expect(() => BookingService.cancelByDriver(id), throwsStateError);
    expect((await db.collection('loads').doc(loadId).get())['status'], LoadStatus.matched);
  });

  testWidgets('trip screen: cancel button only before pickup', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late String id;
    await tester.runAsync(() async => id = await acceptedBooking());

    await tester.pumpWidget(MaterialApp(home: DriverTripScreen(bookingId: id)));
    await settle(tester);
    await tester.ensureVisible(find.text('Cancel booking'));
    await tester.tap(find.text('Cancel booking'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await settle(tester);

    expect(find.text('Booking cancelled'), findsWidgets);
    expect(find.text('Cancelled'), findsWidgets);
    expect(find.text('Mark Picked Up'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cancel booking'), findsNothing);
  });
}
