import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/rating.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/rating_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/customer/booking_tracking_screen.dart';
import 'package:transport_app/core/profile/profile_view.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
  });

  var vehicleCount = 0;

  /// Creates a booking between customer1 and driver1, advanced [steps] times.
  Future<Booking> booking({int steps = 3}) async {
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000,
        pickupDate: DateTime(2026, 10, 5), notes: '');
    uid = 'driver1';
    // A fresh vehicle per booking: the previous one may still be on a trip.
    final vehicleId = await VehicleService.add(number: 'MH12AB${1000 + vehicleCount++}', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).firstWhere((v) => v.id == vehicleId);
    final id = await BookingService.accept(loadId: loadId, vehicle: vehicle);
    await advanceTo(id, steps >= 3 ? BookingStatus.delivered : BookingStatus.inTransit);
    return Booking.fromDoc(await db.collection('bookings').doc(id).get());
  }

  test('RatingSummary averages stars', () {
    expect(RatingSummary.of(const []).count, 0);
    final s = RatingSummary.of([
      for (final n in [5, 4, 3]) Rating(id: '$n', bookingId: 'b', raterId: 'r', ratedId: 'x', stars: n, comment: ''),
    ]);
    expect(s.average, 4.0);
    expect(s.count, 3);
  });

  test('both parties rate once after delivery; summary updates', () async {
    final b = await booking();
    uid = 'customer1';
    await RatingService.rate(booking: b, stars: 5, comment: ' Great ');
    expect(() => RatingService.rate(booking: b, stars: 1), throwsA(isA<AlreadyRatedException>()));
    uid = 'driver1';
    await RatingService.rate(booking: b, stars: 4);

    final mine = (await db.collection('ratings').doc('${b.id}_customer1').get()).data()!;
    expect(mine['ratedId'], 'driver1');
    expect(mine['comment'], 'Great');
    final driverSummary = await RatingService.watchSummary('driver1').first;
    expect(driverSummary.average, 5);
    expect((await RatingService.watchSummary('customer1').first).average, 4);
  });

  test('cannot rate before delivery, as an outsider, or out of range', () async {
    final b = await booking(steps: 2);
    uid = 'customer1';
    expect(() => RatingService.rate(booking: b, stars: 5), throwsStateError);
    final delivered = await booking();
    expect(() => RatingService.rate(booking: delivered, stars: 0), throwsArgumentError);
    uid = 'driver2';
    expect(() => RatingService.rate(booking: delivered, stars: 5), throwsStateError);
  });

  testWidgets('customer rates the driver from the tracking screen', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Booking b;
    await tester.runAsync(() async => b = await booking());
    uid = 'customer1';

    await tester.pumpWidget(MaterialApp(home: BookingTrackingScreen(bookingId: b.id)));
    await settle(tester);
    expect(find.text('Rate your driver'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('star4')));
    await tester.tap(find.byKey(const ValueKey('star4')));
    await tester.pump();
    await tester.ensureVisible(find.text('Submit rating'));
    await tester.tap(find.text('Submit rating'));
    await settle(tester);

    expect(find.text('Your rating'), findsOneWidget);
    expect(find.text('Submit rating'), findsNothing);
    expect((await db.collection('ratings').doc('${b.id}_customer1').get())['stars'], 4);
    // Driver badge now shows the average.
    expect(find.text('4.0'), findsOneWidget);
  });

  testWidgets('profile shows name, phone and average rating', (tester) async {
    await tester.runAsync(() async {
      await db.collection('users').doc('driver1').set({'driverName': 'Ramesh', 'phone': '+919800000000'});
      await db.collection('ratings').doc('a').set({'ratedId': 'driver1', 'stars': 5});
      await db.collection('ratings').doc('b').set({'ratedId': 'driver1', 'stars': 4});
    });
    uid = 'driver1';
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ProfileView(isDriver: true))));
    await settle(tester);
    expect(find.text('Ramesh'), findsOneWidget);
    expect(find.text('+91 98•••••000'), findsOneWidget);
    expect(find.text('4.5 (2 ratings)'), findsOneWidget);
  });
}
