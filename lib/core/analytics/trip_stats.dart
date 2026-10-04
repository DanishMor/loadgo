import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/load.dart';
import '../models/offer.dart';
import '../pricing/cities.dart';

/// "Delhi → Mumbai" with city names normalised through the city table, so
/// "Andheri, Mumbai" and "bombay" count as the same place.
String routeKey(String pickup, String drop) {
  String name(String s) => findCity(s)?.name ?? s.trim();
  return '${name(pickup)} → ${name(drop)}';
}

class RouteCount {
  final String route;
  final int count;
  const RouteCount(this.route, this.count);
}

num? _rate(int part, int whole) => whole == 0 ? null : part / whole;

/// A customer's shipping history, from their loads and bookings.
class CustomerStats {
  final int shipments;
  final int delivered;
  final int cancelled;

  /// Billed amount of delivered bookings (paise).
  final int spendPaise;

  /// Delivered / (delivered + cancelled loads); null when neither happened.
  final num? successRate;
  final List<RouteCount> topRoutes;

  const CustomerStats({
    required this.shipments,
    required this.delivered,
    required this.cancelled,
    required this.spendPaise,
    required this.successRate,
    required this.topRoutes,
  });

  factory CustomerStats.from(Iterable<Load> loads, Iterable<Booking> bookings, {int topRoutes = 5}) {
    final done = bookings.where((b) => b.status == BookingStatus.delivered).toList();
    final cancelled = loads.where((l) => l.cancelled).length;
    return CustomerStats(
      shipments: loads.length,
      delivered: done.length,
      cancelled: cancelled,
      spendPaise: done.fold(0, (s, b) => s + (b.billAmountPaise ?? 0)),
      successRate: _rate(done.length, done.length + cancelled),
      topRoutes: _topRoutes([for (final l in loads) routeKey(l.pickup, l.drop)], topRoutes),
    );
  }
}

/// A driver's work history, from their bookings and price offers.
class DriverStats {
  final int trips;
  final int cancelledTrips;
  final int earningsPaise;

  /// Offers the customer picked / offers decided (picked + rejected).
  final num? acceptanceRate;

  /// Cancelled / all bookings; null without bookings.
  final num? cancelRate;
  final List<RouteCount> topRoutes;

  const DriverStats({
    required this.trips,
    required this.cancelledTrips,
    required this.earningsPaise,
    required this.acceptanceRate,
    required this.cancelRate,
    required this.topRoutes,
  });

  factory DriverStats.from(Iterable<Booking> bookings, Iterable<Offer> offers, {int topRoutes = 5}) {
    final done = bookings.where((b) => b.status == BookingStatus.delivered).toList();
    final cancelled = bookings.where((b) => b.status == BookingStatus.cancelled).length;
    final won = offers.where((o) => o.status == OfferStatus.selected || o.status == OfferStatus.confirmed).length;
    final lost = offers.where((o) => o.status == OfferStatus.rejected).length;
    return DriverStats(
      trips: done.length,
      cancelledTrips: cancelled,
      earningsPaise: done.fold(0, (s, b) => s + (b.billAmountPaise ?? 0)),
      acceptanceRate: _rate(won, won + lost),
      cancelRate: _rate(cancelled, bookings.length),
      topRoutes: _topRoutes([for (final b in done) routeKey(b.pickup, b.drop)], topRoutes),
    );
  }
}

List<RouteCount> _topRoutes(List<String> keys, int n) {
  final counts = <String, int>{};
  for (final k in keys) {
    counts[k] = (counts[k] ?? 0) + 1;
  }
  final list = [for (final e in counts.entries) RouteCount(e.key, e.value)]
    ..sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.route.compareTo(b.route);
    });
  return list.take(n).toList();
}

/// Whole-percent text like "75%".
String percentText(num rate) => '${(rate * 100).round()}%';
