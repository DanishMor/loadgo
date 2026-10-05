import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_rating_flags_screen.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/rating.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/rating_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/widgets/rating_widgets.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<Booking> delivered() async {
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000,
        pickupDate: DateTime(2026, 10, 5), notes: '');
    uid = 'driver1';
    final vid = await VehicleService.add(number: 'MH12AB1000', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).firstWhere((v) => v.id == vid);
    final id = await BookingService.accept(loadId: loadId, vehicle: vehicle);
    await advanceTo(id, BookingStatus.delivered);
    return Booking.fromDoc(await db.collection('bookings').doc(id).get());
  }

  test('summary averages each category separately', () {
    final s = RatingSummary.of([
      const Rating(id: 'a', bookingId: 'b', raterId: 'x', ratedId: 'y', stars: 5, comment: '', cats: {'time': 5, 'safety': 4}),
      const Rating(id: 'b', bookingId: 'b', raterId: 'x', ratedId: 'y', stars: 4, comment: '', cats: {'time': 3}),
      const Rating(id: 'c', bookingId: 'b', raterId: 'x', ratedId: 'y', stars: 3, comment: ''),
    ]);
    expect(s.average, 4);
    expect(s.categoryAverages, {'time': 4.0, 'safety': 4.0});
  });

  test('categories are stored; bad ones are refused; 4+ stars opens no flag', () async {
    final b = await delivered();
    uid = 'customer1';
    expect(() => RatingService.rate(booking: b, stars: 5, cats: {'speed': 3}), throwsArgumentError);
    expect(() => RatingService.rate(booking: b, stars: 5, cats: {'time': 6}), throwsArgumentError);
    await RatingService.rate(booking: b, stars: 4, cats: {'time': 5, 'behaviour': 4, 'safety': 3});
    expect((await db.collection('ratings').doc('${b.id}_customer1').get())['cats'], {'time': 5, 'behaviour': 4, 'safety': 3});
    expect((await db.collection('rating_flags').get()).docs, isEmpty);
    expect((await RatingService.watchSummary('driver1').first).categoryAverages['safety'], 3);
  });

  test('under 3 stars writes a flag both ways; admin resolves it', () async {
    final b = await delivered();
    uid = 'customer1';
    await RatingService.rate(booking: b, stars: 2, comment: 'late');
    uid = 'driver1';
    await RatingService.rate(booking: b, stars: 1);
    final flags = await RatingService.watchFlags().first;
    expect(flags.map((f) => (f.ratedId, f.stars, f.status)).toSet(), {('driver1', 2, 'open'), ('customer1', 1, 'open')});
    expect((await RatingService.watchReceived('driver1').first).single.isLow, isTrue);
    uid = 'admin1';
    await RatingService.resolveFlag(flags.first.id, RatingFlag.reviewed);
    expect(() => RatingService.resolveFlag(flags.first.id, 'open'), throwsArgumentError);
    expect((await db.collection('rating_flags').doc(flags.first.id).get())['handledBy'], 'admin1');
  });

  testWidgets('prompt sends category scores; reviews and admin screens list them', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Booking b;
    await tester.runAsync(() async => b = await delivered());
    uid = 'customer1';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RatingPrompt(booking: b, titleKey: 'rateDriver')))));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('star2')));
    await tester.tap(find.byKey(const ValueKey('cat_time_1')));
    await tester.tap(find.byKey(const ValueKey('cat_safety_5')));
    await tester.pump();
    await tester.tap(find.text('Submit rating'));
    await settle(tester);
    final saved = (await db.collection('ratings').doc('${b.id}_customer1').get()).data()!;
    expect(saved['cats'], {'time': 1, 'safety': 5});

    uid = 'driver1';
    await tester.pumpWidget(const MaterialApp(home: ReviewsScreen(userId: 'driver1')));
    await settle(tester);
    expect(find.text('Safety of goods'), findsWidgets);
    uid = 'admin1';
    await tester.pumpWidget(const MaterialApp(home: AdminRatingFlagsScreen()));
    await settle(tester);
    expect(find.textContaining('2 stars'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await settle(tester);
    expect((await db.collection('rating_flags').get()).docs.single['status'], 'dismissed');
  });
}
