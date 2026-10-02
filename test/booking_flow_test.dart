import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/features/bookings/booking_tracking_screen.dart';
import 'package:transport_app/features/bookings/driver_trip_screen.dart';

/// Fake Firestore futures complete on real async while spinners animate.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  }
  await tester.pumpAndSettle();
}

/// Waits out the floating "Status updated" snackbar so it can't absorb taps.
Future<void> tapButton(WidgetTester tester, String label) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
}

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
  });

  /// Customer posts a load, driver1 accepts it. Leaves driver1 signed in.
  Future<String> createBooking() async {
    uid = 'customer1';
    final loadId = await LoadService.post(
      pickup: 'Delhi',
      drop: 'Mumbai',
      cargoType: 'FMCG',
      weight: 8,
      vehicleType: '20ft',
      budget: null,
      pickupDate: DateTime(2026, 10, 5),
      notes: '',
    );
    uid = 'driver1';
    await db.collection('users').doc('driver1').set({'driverName': 'Ramesh', 'phone': '+919800000000'});
    await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).single;
    return BookingService.accept(loadId: loadId, vehicle: vehicle);
  }

  test('BookingStatus.next follows the lifecycle', () {
    expect(BookingStatus.next(BookingStatus.accepted), BookingStatus.pickedUp);
    expect(BookingStatus.next(BookingStatus.pickedUp), BookingStatus.inTransit);
    expect(BookingStatus.next(BookingStatus.inTransit), BookingStatus.delivered);
    expect(BookingStatus.next(BookingStatus.delivered), isNull);
    expect(BookingStatus.next('bogus'), isNull);
  });

  test('driver advances accepted -> picked_up -> in_transit -> delivered', () async {
    final id = await createBooking();
    final loadId = (await db.collection('bookings').doc(id).get())['loadId'] as String;

    expect(await BookingService.advance(id), BookingStatus.pickedUp);
    expect(await BookingService.advance(id), BookingStatus.inTransit);
    expect((await db.collection('loads').doc(loadId).get())['status'], LoadStatus.matched);
    expect(await BookingService.advance(id), BookingStatus.delivered);

    final booking = Booking.fromDoc(await db.collection('bookings').doc(id).get());
    expect(booking.status, BookingStatus.delivered);
    expect(booking.timeline.keys, containsAll(BookingStatus.flow));
    expect(booking.isActive, isFalse);
    expect((await db.collection('loads').doc(loadId).get())['status'], LoadStatus.closed);

    expect(() => BookingService.advance(id), throwsStateError);
  });

  test('only the assigned driver can advance', () async {
    final id = await createBooking();
    uid = 'customer1';
    expect(() => BookingService.advance(id), throwsStateError);
    uid = 'driver2';
    expect(() => BookingService.advance(id), throwsStateError);
    expect((await db.collection('bookings').doc(id).get())['status'], BookingStatus.accepted);
  });

  testWidgets('driver trip screen advances status; customer sees it live', (tester) async {
    late String id;
    await tester.runAsync(() async => id = await createBooking());

    await tester.pumpWidget(MaterialApp(home: DriverTripScreen(bookingId: id)));
    await settle(tester);
    expect(find.text('Delhi → Mumbai'), findsOneWidget);
    expect(find.text('Mark Picked Up'), findsOneWidget);

    await tapButton(tester, 'Mark Picked Up');
    await settle(tester);
    expect(find.text('Start Trip (In Transit)'), findsOneWidget);

    await tapButton(tester, 'Start Trip (In Transit)');
    await settle(tester);
    await tapButton(tester, 'Mark Delivered');
    await tester.pumpAndSettle();
    // Confirmation dialog, then confirm.
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await settle(tester);
    expect(find.text('Trip completed'), findsOneWidget);

    // Customer tracking screen reflects the delivered state and driver info.
    uid = 'customer1';
    await tester.pumpWidget(MaterialApp(home: BookingTrackingScreen(bookingId: id)));
    await settle(tester);
    expect(find.text('Delivered'), findsWidgets);
    expect(find.text('Ramesh • +919800000000'), findsOneWidget);
    expect(find.text('Mark Delivered'), findsNothing);
  });

  testWidgets('customer tracking updates in real time', (tester) async {
    late String id;
    await tester.runAsync(() async => id = await createBooking());
    uid = 'customer1';

    await tester.pumpWidget(MaterialApp(home: BookingTrackingScreen(bookingId: id)));
    await settle(tester);
    expect(find.text('Accepted'), findsWidgets);

    await tester.runAsync(() async {
      uid = 'driver1';
      await BookingService.advance(id);
      uid = 'customer1';
    });
    await settle(tester);
    // Chip in the summary shows the new status.
    expect(find.text('Picked up'), findsNWidgets(2));
  });
}
