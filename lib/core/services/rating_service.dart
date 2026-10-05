import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/app_notification.dart';
import '../models/booking.dart';
import '../models/rating.dart';
import 'backend.dart';
import 'notification_service.dart';

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
  static Future<void> rate({required Booking booking, required int stars, String comment = '', Map<String, int> cats = const {}}) async {
    final uid = Backend.requireUid();
    if (booking.status != BookingStatus.delivered) throw StateError('Only delivered bookings can be rated');
    if (stars < 1 || stars > 5) throw ArgumentError.value(stars, 'stars', 'must be 1-5');
    for (final e in cats.entries) {
      if (!RatingCategory.all.contains(e.key) || e.value < 1 || e.value > 5) throw ArgumentError.value(cats, 'cats');
    }
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
          if (cats.isNotEmpty) 'cats': cats,
          'createdAt': FieldValue.serverTimestamp(),
        });
        // Below 3 stars: the admin sees it in Rating flags. TODO(functions): open this server side.
        if (stars < lowRatingStars) {
          tx.set(Backend.db.collection('rating_flags').doc(ref.id), {
            'bookingId': booking.id,
            'raterId': uid,
            'ratedId': ratedId,
            'stars': stars,
            'status': RatingFlag.open,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        NotificationService.addInTransaction(
          tx,
          userId: ratedId,
          type: NotificationType.ratingReceived,
          message: '$stars★ · ${booking.pickup} → ${booking.drop}',
          relatedId: booking.id,
        );
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

  /// Reviews [userId] received, newest first.
  static Stream<List<Rating>> watchReceived(String userId) => _col.where('ratedId', isEqualTo: userId).snapshots().map((snap) {
        final list = snap.docs.map(Rating.fromDoc).toList();
        list.sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 1 << 50).compareTo(a.createdAt?.millisecondsSinceEpoch ?? 1 << 50));
        return list;
      });

  // ---- admin: low-rating flags ----

  static CollectionReference<Map<String, dynamic>> get _flags => Backend.db.collection('rating_flags');

  static Stream<List<RatingFlag>> watchFlags() => _flags.snapshots().map((s) {
        final list = [for (final d in s.docs) RatingFlag.fromDoc(d.id, d.data())];
        list.sort((a, b) => (a.status == RatingFlag.open ? 0 : 1).compareTo(b.status == RatingFlag.open ? 0 : 1));
        return list;
      });

  static Future<void> resolveFlag(String id, String status) {
    if (status != RatingFlag.reviewed && status != RatingFlag.dismissed) throw ArgumentError.value(status, 'status');
    return _flags.doc(id).update({'status': status, 'handledBy': Backend.requireUid(), 'handledAt': FieldValue.serverTimestamp()});
  }
}
