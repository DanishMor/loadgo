import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/rating.dart';
import 'backend.dart';

class AlreadyRatedException implements Exception {
  @override
  String toString() => 'AlreadyRatedException';
}

class RatingService {
  RatingService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      Backend.db.collection('ratings');

  /// One rating per rater per booking: the id encodes both.
  static String ratingId(String bookingId, String raterId) => '${bookingId}_$raterId';

  /// The signed-in user rates the other party of a delivered [booking].
  static Future<void> rate({required Booking booking, required int stars, String comment = ''}) async {
    final uid = Backend.requireUid();
    if (booking.status != BookingStatus.delivered) throw StateError('Only delivered bookings can be rated');
    if (stars < 1 || stars > 5) throw ArgumentError.value(stars, 'stars', 'must be 1-5');
    final String ratedId;
    if (uid == booking.driverId) {
      ratedId = booking.customerId;
    } else if (uid == booking.customerId) {
      ratedId = booking.driverId;
    } else {
      throw StateError('Not part of this booking');
    }

    final ref = _col.doc(ratingId(booking.id, uid));
    try {
      await Backend.db.runTransaction((tx) async {
        if ((await tx.get(ref)).exists) throw AlreadyRatedException();
        tx.set(ref, {
          'bookingId': booking.id,
          'raterId': uid,
          'ratedId': ratedId,
          'stars': stars,
          'comment': comment.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (e) {
      // Rules deny overwriting an existing rating.
      if (e.code == 'permission-denied') throw AlreadyRatedException();
      rethrow;
    }
  }

  /// The signed-in user's rating for [bookingId], or null if not rated yet.
  static Stream<Rating?> watchMine(String bookingId) {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(null);
    return _col.doc(ratingId(bookingId, uid)).snapshots().map((s) => s.exists ? Rating.fromDoc(s) : null);
  }

  static Stream<RatingSummary> watchSummary(String userId) {
    return _col
        .where('ratedId', isEqualTo: userId)
        .snapshots()
        .map((snap) => RatingSummary.of(snap.docs.map(Rating.fromDoc)));
  }
}
