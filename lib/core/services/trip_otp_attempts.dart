import 'package:cloud_firestore/cloud_firestore.dart';

import 'audit_service.dart';
import 'backend.dart';

/// The trip code entry is locked (5 wrong guesses). [remaining] is what is left of the 15 minutes.
class OtpLockedException implements Exception {
  final Duration remaining;
  OtpLockedException(this.remaining);
}

/// What the counter says after a guess was stored.
class GuessState {
  final int count;
  final Duration? lockedFor;
  const GuessState(this.count, this.lockedFor);
  int get attemptsLeft => lockedFor != null ? 0 : TripOtpAttempts.maxAttempts - count;
}

/// F2: every guess at a pickup or delivery code is written to
/// `bookings/{id}/otp_attempts/{pickup|delivery}` BEFORE the booking step, with
/// a counter that goes up by one (Firestore rules cannot count the requests
/// they refuse). The 5th guess locks the entry for 15 minutes from `guessAt`.
/// The rules accept the booking step only with a stored guess equal to the
/// customer's secret, and the step resets the counter in the same batch.
class TripOtpAttempts {
  TripOtpAttempts._();

  static const maxAttempts = 5;
  static const lockMinutes = 15;
  static const pickup = 'pickup';
  static const delivery = 'delivery';

  static DocumentReference<Map<String, dynamic>> ref(String bookingId, String kind) =>
      Backend.db.collection('bookings').doc(bookingId).collection('otp_attempts').doc(kind);

  /// Time left on the lock in [data] (a stored attempts document), or null.
  /// Defensive: a missing or odd document means "not locked".
  static Duration? lockRemaining(Map<String, dynamic>? data, DateTime now) {
    if (data == null) return null;
    final count = data['count'];
    final at = data['guessAt'];
    if (count is! int || count < maxAttempts || at is! Timestamp) return null;
    final until = at.toDate().add(const Duration(minutes: lockMinutes));
    return until.isAfter(now) ? until.difference(now) : null;
  }

  /// The count that the next stored guess must carry.
  static int nextCount(Map<String, dynamic>? data, DateTime now) {
    if (data == null) return 1;
    final count = data['count'];
    if (count is! int || count < 0) return 1;
    if (count >= maxAttempts) return lockRemaining(data, now) == null ? 1 : maxAttempts + 1;
    return count + 1;
  }

  /// Stores [guess]. Throws [OtpLockedException] while locked. The 5th guess
  /// also writes an admin audit line in the same transaction.
  static Future<GuessState> recordGuess(String bookingId, String kind, String guess, {DateTime? now}) async {
    final uid = Backend.requireUid();
    final clock = now ?? DateTime.now();
    final r = ref(bookingId, kind);
    final bref = Backend.db.collection('bookings').doc(bookingId);
    return Backend.db.runTransaction((tx) async {
      final snap = await tx.get(r);
      final data = snap.data();
      final left = lockRemaining(data, clock);
      if (left != null) throw OtpLockedException(left);
      final count = nextCount(data, clock);
      String? customerId;
      if (count == maxAttempts) {
        final b = (await tx.get(bref)).data();
        final c = b?['customerId'];
        customerId = c is String ? c : null;
      }
      tx.set(r, {'count': count, 'guess': guess, 'guessAt': FieldValue.serverTimestamp(), 'actorId': uid});
      if (count == maxAttempts) {
        AuditService.inTransaction(tx, AuditType.otpLock,
            targetId: customerId, bookingId: bookingId, data: {'kind': kind, 'minutes': lockMinutes});
      }
      return GuessState(count, count == maxAttempts ? const Duration(minutes: lockMinutes) : null);
    });
  }

  /// The customer (or the driver) reading the lock, e.g. for the notice card.
  static Stream<Duration?> watchLock(String bookingId, String kind) => Backend.db
      .collection('bookings')
      .doc(bookingId)
      .collection('otp_attempts')
      .doc(kind)
      .snapshots()
      .map((s) => lockRemaining(s.data(), DateTime.now()))
      .handleError((_) {});
}
