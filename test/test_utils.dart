import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';

/// Fake Firestore futures complete on real async while spinners animate, so
/// interleave frames with real time before settling.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  }
  await tester.pumpAndSettle();
}

/// Drives a booking forward until it reaches [target], supplying an OTP and
/// proof where the flow needs them (fake Firestore has no rules to check the
/// OTP against).
Future<void> advanceTo(String bookingId, String target) async {
  for (var i = 0; i < BookingStatus.flow.length; i++) {
    final snap = await Backend.db.collection('bookings').doc(bookingId).get();
    if (snap.data()?['status'] == target) return;
    await BookingService.advance(
      bookingId,
      otp: '123456',
      pickup: const PickupProof(packages: 10, weightTons: 2),
      delivery: const DeliveryProof(receiverName: 'Anil'),
    );
  }
}
