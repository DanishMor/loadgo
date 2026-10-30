import 'trust_badges.dart';

/// E34 (flag reliabilityBadges): a driver's reliability tier. The same formula as the server
/// (functions/src/trust.js reliabilityTier) and docs/RELIABILITY.md. Customers only ever see the tier as a badge,
/// never the numbers.
enum ReliabilityTier { top, good }

class Reliability {
  Reliability._();

  static const minTrips = 10;

  /// 0..100, or null with fewer than [minTrips] finished trips (delivered + cancelled by the driver).
  static int? score({required int delivered, required int driverCancelled, int onTimeKnown = 0, int onTimeOk = 0, double? rating, int ratingCount = 0}) {
    int n(int x) => x < 0 ? 0 : x;
    final d = n(delivered), c = n(driverCancelled), known = n(onTimeKnown);
    final ok = n(onTimeOk) > known ? known : n(onTimeOk);
    final finished = d + c;
    if (finished < minTrips) return null;
    final completion = d / finished;
    final onTime = known >= 5 ? ok / known : completion;
    final stars = ratingCount >= 5 && rating != null && rating.isFinite ? rating.clamp(0, 5) / 5 : 0.9;
    return (60 * completion + 25 * onTime + 15 * stars).round();
  }

  static ReliabilityTier? tierOf(int? score) => score == null ? null : (score >= 92 ? ReliabilityTier.top : (score >= 82 ? ReliabilityTier.good : null));

  /// The tier from the badges the app already works out from a driver's own bookings.
  static ReliabilityTier? fromBadges(TrustBadges b, {double? rating, int ratingCount = 0}) {
    final cancelled = b.finished - b.delivered;
    final ok = (b.onTimePercent * b.onTimeKnown / 100).round();
    return tierOf(score(delivered: b.delivered, driverCancelled: cancelled, onTimeKnown: b.onTimeKnown, onTimeOk: ok, rating: rating, ratingCount: ratingCount));
  }

  /// The tier the server wrote to public_trust ('top' or 'good'); anything else is no tier.
  static ReliabilityTier? parse(Object? v) => switch (v) { 'top' => ReliabilityTier.top, 'good' => ReliabilityTier.good, _ => null };
}
