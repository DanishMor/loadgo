import '../constants/logistics.dart';
import 'booking.dart';

/// Driver earnings derived from delivered bookings. Until fares exist, the
/// load's budget is treated as the earning (negotiable loads count as 0).
class EarningsSummary {
  final num total;
  final num thisWeek;
  final num today;
  final int completedTrips;

  /// Delivered bookings, most recent delivery first.
  final List<Booking> delivered;

  const EarningsSummary({
    required this.total,
    required this.thisWeek,
    required this.today,
    required this.completedTrips,
    required this.delivered,
  });

  static DateTime deliveredAt(Booking b) =>
      b.timeline[BookingStatus.delivered] ?? b.createdAt?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Weeks start on Monday 00:00 local time.
  static DateTime startOfWeek(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  factory EarningsSummary.from(Iterable<Booking> bookings, DateTime now) {
    final delivered = bookings.where((b) => b.status == BookingStatus.delivered).toList()
      ..sort((a, b) => deliveredAt(b).compareTo(deliveredAt(a)));
    final weekStart = startOfWeek(now);
    final dayStart = DateTime(now.year, now.month, now.day);
    num total = 0, week = 0, today = 0;
    for (final b in delivered) {
      final amount = b.budget ?? 0;
      final at = deliveredAt(b);
      total += amount;
      if (!at.isBefore(weekStart)) week += amount;
      if (!at.isBefore(dayStart)) today += amount;
    }
    return EarningsSummary(
      total: total,
      thisWeek: week,
      today: today,
      completedTrips: delivered.length,
      delivered: delivered,
    );
  }
}
