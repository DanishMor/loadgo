import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'backend.dart';

/// The customer's pickup and delivery codes for one booking.
class TripOtps {
  final String pickupOtp;
  final String deliveryOtp;
  const TripOtps(this.pickupOtp, this.deliveryOtp);
}

/// `bookings/{id}/secrets/otp`, created by the customer and readable only by
/// them. The driver types the code; Firestore rules compare it with this
/// document, so the code never has to be readable by the driver.
///
/// TODO(functions): rate-limit wrong OTP attempts server-side.
class TripOtpService {
  TripOtpService._();

  static final _random = Random.secure();

  static DocumentReference<Map<String, dynamic>> _ref(String bookingId) =>
      Backend.db.collection('bookings').doc(bookingId).collection('secrets').doc('otp');

  static String newOtp() => (_random.nextInt(900000) + 100000).toString();

  /// Customer side: returns the codes, creating them on first use.
  static Future<TripOtps> ensure(String bookingId) async {
    final ref = _ref(bookingId);
    final snap = await ref.get();
    final d = snap.data();
    if (d != null) return TripOtps(d['pickupOtp'] as String, d['deliveryOtp'] as String);
    final otps = TripOtps(newOtp(), newOtp());
    try {
      await ref.set({'pickupOtp': otps.pickupOtp, 'deliveryOtp': otps.deliveryOtp, 'createdAt': FieldValue.serverTimestamp()});
    } on FirebaseException {
      // Another device created them first (rules refuse overwriting).
      final again = (await ref.get()).data();
      if (again == null) rethrow;
      return TripOtps(again['pickupOtp'] as String, again['deliveryOtp'] as String);
    }
    return otps;
  }
}
