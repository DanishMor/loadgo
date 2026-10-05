import 'package:cloud_firestore/cloud_firestore.dart';

import 'backend.dart';

/// The user hit the hourly limit for [kind] ('load', 'offer' or 'message').
class RateLimitException implements Exception {
  final String kind;
  final int minutesLeft;
  RateLimitException(this.kind, this.minutesLeft);
  @override
  String toString() => 'RateLimitException($kind, $minutesLeft min)';
}

/// What one counted action writes: the counter document `rate_limits/{uid}_{kind}`
/// is bumped in the same batch as the action. The rules check the bump and
/// the limit (keep [RateLimit.limits] in sync with `rateLimitFor`).
class RateBump {
  final DocumentReference<Map<String, dynamic>> ref;
  final int count;

  /// Kept window start, or null to start a new window (server time).
  final Timestamp? windowStart;

  /// Id of the document this bump pays for (one document per bump).
  final String last;

  const RateBump(this.ref, this.count, this.windowStart, this.last);

  Map<String, Object?> get data => {
    'count': count,
    'windowStart': windowStart ?? FieldValue.serverTimestamp(),
    'last': last,
  };

  void addToBatch(WriteBatch batch) => batch.set(ref, data);

  void addToTransaction(Transaction tx) => tx.set(ref, data);
}

class RateLimit {
  RateLimit._();

  static const loadKind = 'load';
  static const offerKind = 'offer';
  static const messageKind = 'message';

  /// Per user per hour.
  static const limits = {loadKind: 30, offerKind: 60, messageKind: 120};

  static const window = Duration(hours: 1);

  /// Reads the counter and returns what to write with the action, or throws
  /// [RateLimitException] when the hour's limit is used up.
  static Future<RateBump> prepare(
    String kind, {
    required String docId,
    DateTime? now,
  }) async {
    final uid = Backend.requireUid();
    final limit = limits[kind]!;
    final ref = Backend.db.collection('rate_limits').doc('${uid}_$kind');
    final data = (await ref.get()).data();
    final t = now ?? DateTime.now();
    final start = data?['windowStart'] as Timestamp?;
    final active = start != null && start.toDate().add(window).isAfter(t);
    final used = active ? (data!['count'] as num).toInt() : 0;
    if (used >= limit) {
      final left = start!.toDate().add(window).difference(t).inMinutes + 1;
      throw RateLimitException(kind, left);
    }
    return RateBump(ref, used + 1, active ? start : null, docId);
  }
}
