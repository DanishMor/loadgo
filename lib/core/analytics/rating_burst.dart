import '../models/rating.dart';

/// One user who gave many 1-star ratings in a short time.
class RatingBurstEntry {
  final String raterId;
  final int oneStarCount;

  /// How many different people they rated 1 star.
  final int distinctRated;
  final DateTime latest;
  const RatingBurstEntry({required this.raterId, required this.oneStarCount, required this.distinctRated, required this.latest});
}

/// Finds raters with [minOneStars] or more 1-star ratings within [window]
/// before [now] (a sign of revenge or review bombing). Biggest first.
class RatingBurst {
  RatingBurst._();

  static const defaultMin = 5;
  static const defaultWindow = Duration(hours: 24);

  static List<RatingBurstEntry> find(
    Iterable<Rating> ratings,
    DateTime now, {
    int minOneStars = defaultMin,
    Duration window = defaultWindow,
  }) {
    final from = now.subtract(window);
    final byRater = <String, List<Rating>>{};
    for (final r in ratings) {
      final at = r.createdAt?.toDate();
      if (r.stars != 1 || at == null || r.raterId.isEmpty) continue;
      if (at.isBefore(from) || at.isAfter(now)) continue;
      byRater.putIfAbsent(r.raterId, () => []).add(r);
    }
    final out = [
      for (final e in byRater.entries)
        if (e.value.length >= minOneStars)
          RatingBurstEntry(
            raterId: e.key,
            oneStarCount: e.value.length,
            distinctRated: e.value.map((r) => r.ratedId).toSet().length,
            latest: e.value.map((r) => r.createdAt!.toDate()).reduce((a, b) => a.isAfter(b) ? a : b),
          ),
    ];
    out.sort((a, b) {
      final c = b.oneStarCount.compareTo(a.oneStarCount);
      return c != 0 ? c : a.raterId.compareTo(b.raterId);
    });
    return out;
  }
}
