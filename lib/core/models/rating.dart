import 'package:cloud_firestore/cloud_firestore.dart';

class Rating {
  final String id;
  final String bookingId;
  final String raterId;
  final String ratedId;
  final int stars;
  final String comment;
  final Timestamp? createdAt;

  const Rating({
    required this.id,
    required this.bookingId,
    required this.raterId,
    required this.ratedId,
    required this.stars,
    required this.comment,
    this.createdAt,
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
    );
  }
}

/// Average stars and how many ratings a user has received.
class RatingSummary {
  final double average;
  final int count;

  const RatingSummary(this.average, this.count);

  static const empty = RatingSummary(0, 0);

  factory RatingSummary.of(Iterable<Rating> ratings) {
    final list = ratings.toList();
    if (list.isEmpty) return empty;
    final total = list.fold<int>(0, (acc, r) => acc + r.stars);
    return RatingSummary(total / list.length, list.length);
  }
}
