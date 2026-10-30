import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/earnings.dart';
import '../models/vehicle.dart';

/// E22: a driver's level, named from delivered trips only. A label to be proud of, nothing more: no money, no
/// priority and no promise is attached to it (docs/DECISIONS.md).
enum DriverLevel {
  starter(0),
  regular(10),
  pro(50),
  star(200);

  /// Delivered trips needed to reach this level.
  final int from;
  const DriverLevel(this.from);

  static DriverLevel of(int delivered) => values.lastWhere((l) => delivered >= l.from);

  /// The next level, or null at the top.
  DriverLevel? get next => index + 1 < values.length ? values[index + 1] : null;

  /// 0..1 of the way from this level to the next (1 at the top).
  double progress(int delivered) {
    final n = next;
    if (n == null) return 1;
    return ((delivered - from) / (n.from - from)).clamp(0, 1).toDouble();
  }
}

/// Days in a row, ending today or yesterday, with at least one delivered trip (local time). 0 when the last
/// delivery is older than yesterday.
int deliveryStreak(Iterable<Booking> bookings, DateTime now) {
  DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
  final days = {for (final b in bookings) if (b.status == BookingStatus.delivered) day(EarningsSummary.deliveredAt(b))};
  var cursor = day(now);
  if (!days.contains(cursor)) cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  var n = 0;
  while (days.contains(cursor)) {
    n++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return n;
}

/// How the driver's truck papers stand today: expired, running out within 30 days, and fine.
class PaperHealth {
  final int expired;
  final int expiring;
  final int vehicles;
  const PaperHealth({required this.expired, required this.expiring, required this.vehicles});

  factory PaperHealth.of(Iterable<Vehicle> list, DateTime now) {
    var expired = 0, expiring = 0, n = 0;
    for (final v in list) {
      n++;
      final out = v.expiredDocs(now).length;
      expired += out;
      expiring += v.docsExpiringWithin(now).length - out;
    }
    return PaperHealth(expired: expired, expiring: expiring, vehicles: n);
  }

  bool get allGood => expired == 0 && expiring == 0;
}

/// Today's earnings as a share of the driver's own daily goal (0..1); 0 without a goal.
double goalShare(num todayRupees, int? goalRupees) {
  if (goalRupees == null || goalRupees <= 0) return 0;
  return (todayRupees / goalRupees).clamp(0, 1).toDouble();
}
