import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/claims/trip_evidence_timeline.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

Booking _b({Map<String, DateTime>? timeline, PickupProof? pickup, DeliveryProof? delivery, BookingCancellation? cancel}) => Booking(
      id: 'B1', loadId: 'L1', driverId: 'd1', vehicleId: 'v1', customerId: 'c1', status: BookingStatus.delivered, pickup: 'A', drop: 'B', cargoType: 'x', weight: 1,
      vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1234', driverName: 'D', driverPhone: '',
      timeline: timeline ?? const {}, pickupProof: pickup, deliveryProof: delivery, cancellation: cancel,
    );

void main() {
  final t0 = DateTime(2026, 10, 1, 9);

  test('steps follow the time of each status, with the proofs next to the status they belong to', () {
    final steps = TripEvidence.of(_b(
      timeline: {
        BookingStatus.delivered: t0.add(const Duration(hours: 9)),
        BookingStatus.accepted: t0,
        BookingStatus.pickedUp: t0.add(const Duration(hours: 2)),
      },
      pickup: const PickupProof(packages: 10, weightTons: 2, sealNumber: 'S1', damageNote: 'dent'),
      delivery: const DeliveryProof(receiverName: 'Anil', damageNote: ''),
    ));
    expect([for (final s in steps) s.kind], ['status', 'status', 'pickupProof', 'damage', 'status', 'deliveryProof']);
    expect(steps.first.args['status'], BookingStatus.accepted);
    expect(steps[3].args['where'], 'pickup');
    expect(steps.last.args['name'], 'Anil');
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i].at!.isBefore(steps[i - 1].at!), isFalse);
    }
  });

  test('a cancellation is shown with who and the recorded charge; no records give no steps', () {
    final steps = TripEvidence.of(_b(timeline: {BookingStatus.accepted: t0, BookingStatus.cancelled: t0.add(const Duration(minutes: 40))}, cancel: const BookingCancellation(by: 'driver', chargePaise: 5000)));
    expect(steps.last.kind, 'cancelled');
    expect(steps.last.args['charge'], 5000);
    expect(TripEvidence.of(_b()), isEmpty);
  });

  testWidgets('the widget lists the evidence of the booking in plain words', (tester) async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    await db.collection('bookings').doc('B1').set({
      'loadId': 'L1', 'driverId': 'd1', 'customerId': 'c1', 'status': 'delivered', 'pickup': 'A', 'drop': 'B',
      'timeline': {'accepted': t0, 'delivered': t0.add(const Duration(hours: 5))},
      'deliveryProof': {'receiverName': 'Anil', 'receiverPhone': '', 'damageNote': 'one box wet'},
    });
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: Scaffold(body: TripEvidenceTimeline(bookingId: 'B1')))));
    await settle(tester);
    expect(find.textContaining('received by Anil'), findsOneWidget);
    expect(find.textContaining('one box wet'), findsOneWidget);
  });

  test('every line has text in all 12 languages', () {
    for (final k in ['evTitle', 'evNone', 'evPickupProof', 'evDeliveryProof', 'evDamagePickup', 'evDamageDelivery', 'evCancelled']) {
      for (final l in AppLanguage.values) {
        expect(T.get(k, l).trim(), isNotEmpty, reason: '$k ${l.name}');
      }
    }
  });
}
