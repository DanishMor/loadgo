import 'package:cloud_firestore/cloud_firestore.dart';

/// Optional per-topic scores (1-5) on top of the overall stars.
class RatingCategory {
  static const time = 'time';
  static const behaviour = 'behaviour';
  static const safety = 'safety';
  static const all = [time, behaviour, safety];
}

/// A rating below this many stars opens an admin flag.
const lowRatingStars = 3;

class Rating {
  final String id;
  final String bookingId;
  final String raterId;
  final String ratedId;
  final int stars;
  final String comment;
  final Timestamp? createdAt;
  final Map<String, int> cats;

  bool get isLow => stars < lowRatingStars;

  const Rating({
    required this.id,
    required this.bookingId,
    required this.raterId,
    required this.ratedId,
    required this.stars,
    required this.comment,
    this.createdAt,
    this.cats = const {},
  });

  factory Rating.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Rating(
      id: doc.id,
      bookingId: d['bookingId'] as String? ?? '',
      raterId: d['raterId'] as String? ?? '',
      ratedId: d['ratedId'] as String? ?? '',
      stars: (d['stars'] as num? ?? 0).toInt(),
      comment: d['comment'] as String? ?? '',
      createdAt: d['createdAt'] as Timestamp?,
      cats: {
        for (final e in ((d['cats'] as Map?) ?? const {}).entries)
          if (RatingCategory.all.contains(e.key)) e.key as String: (e.value as num).toInt(),
      },
    );
  }
}

/// Average stars, per-category averages and how many ratings a user has received.
class RatingSummary {
  final double average;
  final int count;

  /// Average of each category that at least one rating scored.
  final Map<String, double> categoryAverages;

  const RatingSummary(this.average, this.count, [this.categoryAverages = const {}]);

  static const empty = RatingSummary(0, 0);

  factory RatingSummary.of(Iterable<Rating> ratings) {
    final list = ratings.toList();
    if (list.isEmpty) return empty;
    final total = list.fold<int>(0, (acc, r) => acc + r.stars);
    final cats = <String, double>{};
    for (final c in RatingCategory.all) {
      final scores = [for (final r in list) ?r.cats[c]];
      if (scores.isNotEmpty) cats[c] = scores.reduce((a, b) => a + b) / scores.length;
    }
    return RatingSummary(total / list.length, list.length, cats);
  }
}

/// `rating_flags/{ratingId}`: a rating below [lowRatingStars], for the admin.
class RatingFlag {
  static const open = 'open';
  static const reviewed = 'reviewed';
  static const dismissed = 'dismissed';

  final String id;
  final String bookingId;
  final String raterId;
  final String ratedId;
  final int stars;
  final String status;

  const RatingFlag({required this.id, required this.bookingId, required this.raterId, required this.ratedId, required this.stars, required this.status});

  factory RatingFlag.fromDoc(String id, Map<String, dynamic> d) => RatingFlag(
        id: id,
        bookingId: d['bookingId'] as String? ?? '',
        raterId: d['raterId'] as String? ?? '',
        ratedId: d['ratedId'] as String? ?? '',
        stars: (d['stars'] as num? ?? 0).toInt(),
        status: d['status'] as String? ?? open,
      );
}
