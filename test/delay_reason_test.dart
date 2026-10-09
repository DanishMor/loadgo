import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/safety/share_trip.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/trip/delay_reason.dart';
import 'package:transport_app/core/widgets/trip_eta_card.dart';

import 'test_utils.dart';

/// MASTER-6 Task 18: why a trip is late, and the tracking link share.
void main() {
  final t0 = DateTime(2026, 10, 5, 8, 0);

  Booking trip({String status = 'in_transit', BookingBreakdown? breakdown, List<String> replaced = const [], Detention detention = const Detention(), DateTime? seen}) => Booking(
        id: 'b1', loadId: 'b1', driverId: 'd', vehicleId: 'v', customerId: 'c', status: status, pickup: 'Pune', drop: 'Delhi', cargoType: 'x', weight: 1,
        vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1',
        timeline: {'accepted': t0, 'picked_up': t0.add(const Duration(hours: 2)), 'in_transit': t0.add(const Duration(hours: 2, minutes: 5))},
        breakdown: breakdown,
        replacedVehicleIds: replaced,
        detention: detention,
        locationUpdatedAt: seen,
      );

  final noon = DateTime(2026, 10, 9, 12);

  test('the reason follows a fixed order, from what the app recorded', () {
    expect(DelayReasons.of(trip(breakdown: const BookingBreakdown(note: 'tyre')), noon)!.reason, DelayReason.breakdown);
    expect(DelayReasons.of(trip(breakdown: const BookingBreakdown(), replaced: ['v0']), noon)!.reason, DelayReason.breakdown); // the problem comes first
    expect(DelayReasons.of(trip(replaced: ['v0']), noon)!.reason, DelayReason.vehicleChanged);
    final wait = DelayReasons.of(trip(detention: const Detention(loadingMinutes: 95)), noon)!;
    expect((wait.reason, wait.minutes), (DelayReason.loadingWait, 95));
    expect(DelayReasons.of(trip(detention: const Detention(loadingMinutes: 59)), noon)!.reason, DelayReason.slowRoad); // below the line
    expect(DelayReasons.of(trip(status: 'unloading', detention: const Detention(unloadingMinutes: 70)), noon)!.reason, DelayReason.unloadingWait);
    final gap = DelayReasons.of(trip(seen: noon.subtract(const Duration(minutes: 50))), noon)!;
    expect((gap.reason, gap.minutes), (DelayReason.noSignal, 50));
    expect(DelayReasons.of(trip(seen: noon.subtract(const Duration(minutes: 10))), noon)!.reason, DelayReason.slowRoad);
    expect(DelayReasons.of(trip(), DateTime(2026, 10, 9, 23, 30))!.reason, DelayReason.nightRest);
    expect(DelayReasons.of(trip(), DateTime(2026, 10, 9, 4, 59))!.reason, DelayReason.nightRest);
    expect(DelayReasons.of(trip(), DateTime(2026, 10, 9, 5, 0))!.reason, DelayReason.slowRoad);
  });

  test('a trip that is not on the road has no delay reason', () {
    for (final s in ['accepted', 'driver_arriving', 'loading', 'delivered', 'cancelled']) {
      expect(DelayReasons.of(trip(status: s), noon), isNull, reason: s);
    }
  });

  testWidgets('a late trip says why under the warning; an on-time trip says nothing', (tester) async {
    Future<void> show(Booking b, DateTime now) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: TripEtaCard(booking: b, clock: () => now)))));
      await tester.pump();
    }

    await show(trip(breakdown: const BookingBreakdown(note: 'tyre')), t0.add(const Duration(days: 5)));
    expect(find.text('Why: the driver reported a vehicle problem.'), findsOneWidget);
    await show(trip(detention: const Detention(loadingMinutes: 95)), t0.add(const Duration(days: 5, hours: 4)));
    expect(find.text('Why: loading took 95 minutes.'), findsOneWidget);
    await show(trip(), t0.add(const Duration(hours: 5)));
    expect(find.byKey(const ValueKey('tripDelayWhy')), findsNothing);
  });

  testWidgets('Share tracking link makes a trip link and hands the text to the share sheet; hidden when the feature is off', (tester) async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c');
    String? shared;
    ShareTrackingLinkButton.shareOverride = (t) async => shared = t;
    addTearDown(() => ShareTrackingLinkButton.shareOverride = null);
    await db.collection('bookings').doc('b1').set({'customerId': 'c'});
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: ShareTrackingLinkButton(booking: trip())))));
    await tester.tap(find.byKey(const ValueKey('shareTrackingLink')));
    await settle(tester);
    expect(shared, contains('https://'));
    expect(shared, contains('/trip/'));
    expect(shared, contains('Pune -> Delhi'));
    expect((await db.collection('trip_shares').get()).docs.length, 1);
    FeaturesService.reset();
  });
}
