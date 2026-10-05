import '../constants/logistics.dart';
import '../models/booking.dart';
import '../pricing/cities.dart';
import 'trip_stats.dart';

class DayStat {
  final DateTime day;
  final int bookings;
  final int delivered;

  /// Billed amount of the day's bookings that were not cancelled (paise).
  final int gmvPaise;

  const DayStat(this.day, this.bookings, this.delivered, this.gmvPaise);
}

class CityCount {
  final String city;
  final int count;
  const CityCount(this.city, this.count);
}

/// Platform trends over the last [days] days, worked out from bookings (pure).
/// GMV is a record of booked value (cancelled bookings left out); nothing is
/// settled through LoadGo. Bookings are counted on the day they were made.
class AdminTrends {
  final int days;
  final List<DayStat> daily;
  final int bookings;
  final int delivered;
  final int cancelled;
  final int gmvPaise;
  final int deliveredPaise;

  /// Distinct drivers with a booking (not cancelled) in the period.
  final int activeDrivers;
  final List<RouteCount> topRoutes;
  final List<CityCount> cities;

  const AdminTrends({
    required this.days,
    required this.daily,
    required this.bookings,
    required this.delivered,
    required this.cancelled,
    required this.gmvPaise,
    required this.deliveredPaise,
    required this.activeDrivers,
    required this.topRoutes,
    required this.cities,
  });

  /// Cancelled / all bookings of the period; null when there are none.
  num? get cancellationRate => bookings == 0 ? null : cancelled / bookings;

  static DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime? madeAt(Booking b) => b.createdAt?.toDate() ?? b.timeline[BookingStatus.accepted];

  factory AdminTrends.from(Iterable<Booking> all, {required DateTime now, int days = 30, int top = 5}) {
    final today = dayOf(now);
    final first = today.subtract(Duration(days: days - 1));
    final inRange = [
      for (final b in all)
        if (madeAt(b) case final t? when !dayOf(t).isBefore(first) && !dayOf(t).isAfter(today)) b,
    ];
    final byDay = <DateTime, List<Booking>>{};
    for (final b in inRange) {
      byDay.putIfAbsent(dayOf(madeAt(b)!), () => []).add(b);
    }
    final daily = [
      for (var i = 0; i < days; i++)
        () {
          final day = first.add(Duration(days: i));
          final list = byDay[day] ?? const <Booking>[];
          final live = list.where((b) => b.status != BookingStatus.cancelled);
          return DayStat(
            day,
            list.length,
            list.where((b) => b.status == BookingStatus.delivered).length,
            live.fold(0, (s, b) => s + (b.billAmountPaise ?? 0)),
          );
        }(),
    ];
    final live = inRange.where((b) => b.status != BookingStatus.cancelled).toList();
    final delivered = inRange.where((b) => b.status == BookingStatus.delivered).toList();
    final routeCounts = <String, int>{};
    final cityCounts = <String, int>{};
    for (final b in live) {
      final r = routeKey(b.pickup, b.drop);
      routeCounts[r] = (routeCounts[r] ?? 0) + 1;
      final c = findCity(b.pickup)?.name ?? b.pickup.trim();
      cityCounts[c] = (cityCounts[c] ?? 0) + 1;
    }
    int byCount(int a, int b, String x, String y) => b != a ? b.compareTo(a) : x.compareTo(y);
    final routes = [for (final e in routeCounts.entries) RouteCount(e.key, e.value)]..sort((a, b) => byCount(a.count, b.count, a.route, b.route));
    final cities = [for (final e in cityCounts.entries) CityCount(e.key, e.value)]..sort((a, b) => byCount(a.count, b.count, a.city, b.city));
    return AdminTrends(
      days: days,
      daily: daily,
      bookings: inRange.length,
      delivered: delivered.length,
      cancelled: inRange.where((b) => b.status == BookingStatus.cancelled).length,
      gmvPaise: live.fold(0, (s, b) => s + (b.billAmountPaise ?? 0)),
      deliveredPaise: delivered.fold(0, (s, b) => s + (b.billAmountPaise ?? 0)),
      activeDrivers: {for (final b in live) b.driverId}.length,
      topRoutes: routes.take(top).toList(),
      cities: cities.take(8).toList(),
    );
  }

  static String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _rupees(int paise) => '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  static String _q(String s) => '"${s.replaceAll('"', '""')}"';

  /// Three blocks in one CSV: per day, top routes, pickup cities.
  String toCsv() {
    final rows = <String>['date,bookings,delivered,gmv_rupees'];
    for (final d in daily) {
      rows.add('${_iso(d.day)},${d.bookings},${d.delivered},${_rupees(d.gmvPaise)}');
    }
    rows.add('');
    rows.add('route,bookings');
    for (final r in topRoutes) {
      rows.add('${_q(r.route)},${r.count}');
    }
    rows.add('');
    rows.add('pickup_city,bookings');
    for (final c in cities) {
      rows.add('${_q(c.city)},${c.count}');
    }
    return rows.join('\n');
  }
}
