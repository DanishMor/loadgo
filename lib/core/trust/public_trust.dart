
import '../money/money.dart';
import 'reliability.dart';
import '../services/backend.dart';

/// The safe numbers other people may see about a driver (F19): written by the
/// server (`public_trust/{uid}`), never by an app. No phone, name or papers.
class PublicTrust {
  final String uid;
  final int trips;

  /// Average stars rounded to one decimal, or null when nobody rated yet.
  final double? rating;
  final int ratingCount;
  final bool verified;

  /// `2026-03` (month the person joined) or null.
  final String? since;

  /// E34: the reliability tier the server worked out ('top' or 'good'), or null.
  final ReliabilityTier? reliability;

  const PublicTrust({required this.uid, this.trips = 0, this.rating, this.ratingCount = 0, this.verified = false, this.since, this.reliability});

  bool get hasRating => rating != null && ratingCount > 0;

  /// Defensive: a missing, damaged or odd document gives zeros, never an exception.
  factory PublicTrust.fromMap(String uid, Map<String, dynamic>? d) {
    final m = d ?? const <String, dynamic>{};
    int count(Object? v) => Money.parse(v).paise.clamp(0, 1000000000).toInt();
    final r = m['rating'];
    final stars = r is num && r.isFinite && r >= 0 && r <= 5 ? r.toDouble() : null;
    final since = m['since'];
    return PublicTrust(
      uid: uid,
      trips: count(m['trips']),
      rating: stars,
      ratingCount: count(m['ratingCount']),
      verified: m['verified'] == true,
      since: since is String && RegExp(r'^\d{4}-\d{2}$').hasMatch(since) ? since : null,
      reliability: Reliability.parse(m['reliability']),
    );
  }

  static Stream<PublicTrust?> watch(String uid) =>
      Backend.db.collection('public_trust').doc(uid).snapshots().map((s) => s.exists ? PublicTrust.fromMap(uid, s.data()) : null);
}
