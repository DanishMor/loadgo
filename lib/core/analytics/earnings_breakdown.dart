import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/earnings.dart';

class DayEarning {
  final DateTime day;
  final int paise;
  final int trips;
  const DayEarning(this.day, this.paise, this.trips);
}

class WeekEarning {
  /// Monday 00:00 of the week.
  final DateTime weekStart;
  final int paise;
  final int trips;
  const WeekEarning(this.weekStart, this.paise, this.trips);
}

/// A driver's delivered trips in daily and weekly buckets. Money is integer
/// paise (`Booking.billAmountPaise`); a trip without an amount counts as a
/// trip with 0. Days and weeks are local time, weeks start on Monday.
class EarningsBreakdown {
  final int todayPaise;
  final int weekPaise;
  final int last7Paise;
  final int totalPaise;
  final int trips;

  /// Exactly 7 entries, oldest first, the last one is today.
  final List<DayEarning> last7Days;

  /// The latest [weeks] weeks, oldest first, the last one is this week.
  final List<WeekEarning> weeks;

  const EarningsBreakdown({
    required this.todayPaise,
    required this.weekPaise,
    required this.last7Paise,
    required this.totalPaise,
    required this.trips,
    required this.last7Days,
    required this.weeks,
  });

  int get peakDayPaise => last7Days.fold(0, (m, d) => d.paise > m ? d.paise : m);
  bool get isEmpty => trips == 0;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  factory EarningsBreakdown.from(Iterable<Booking> bookings, DateTime now, {int weeks = 8}) {
    final today = _day(now);
    final days = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    final dayPaise = <DateTime, int>{for (final d in days) d: 0};
    final dayTrips = <DateTime, int>{for (final d in days) d: 0};

    final thisWeek = EarningsSummary.startOfWeek(now);
    final starts = [for (var i = weeks - 1; i >= 0; i--) DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7 * i)];
    final weekPaise = <DateTime, int>{for (final s in starts) s: 0};
    final weekTrips = <DateTime, int>{for (final s in starts) s: 0};

    var total = 0, trips = 0;
    for (final b in bookings) {
      if (b.status != BookingStatus.delivered) continue;
      final paise = b.billAmountPaise ?? 0;
      final at = EarningsSummary.deliveredAt(b);
      final day = _day(at);
      total += paise;
      trips++;
      if (dayPaise.containsKey(day)) {
        dayPaise[day] = dayPaise[day]! + paise;
        dayTrips[day] = dayTrips[day]! + 1;
      }
      final ws = EarningsSummary.startOfWeek(at);
      if (weekPaise.containsKey(ws)) {
        weekPaise[ws] = weekPaise[ws]! + paise;
        weekTrips[ws] = weekTrips[ws]! + 1;
      }
    }
    return EarningsBreakdown(
      todayPaise: dayPaise[today]!,
      weekPaise: weekPaise[thisWeek] ?? 0,
      last7Paise: dayPaise.values.fold(0, (a, b) => a + b),
      totalPaise: total,
      trips: trips,
      last7Days: [for (final d in days) DayEarning(d, dayPaise[d]!, dayTrips[d]!)],
      weeks: [for (final s in starts) WeekEarning(s, weekPaise[s]!, weekTrips[s]!)],
    );
  }
}
