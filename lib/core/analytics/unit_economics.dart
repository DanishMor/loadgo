import '../models/booking.dart';
import 'admin_trends.dart';

/// Costs the admin types in (config/economics), integer paise.
class EconomicsCosts {
  /// Fixed cost of a 30 day period (servers, tools, salaries...).
  final int monthlyFixedPaise;

  /// Cost of serving one delivered trip (support time, SMS, gateway...).
  final int perTripCostPaise;

  const EconomicsCosts({this.monthlyFixedPaise = 0, this.perTripCostPaise = 0});

  static int _paise(Object? v) => v is num && v >= 0 && v < 1000000000000 ? v.round() : 0;

  factory EconomicsCosts.fromMap(Map<String, dynamic>? m) =>
      EconomicsCosts(monthlyFixedPaise: _paise(m?['monthlyFixedPaise']), perTripCostPaise: _paise(m?['perTripCostPaise']));

  Map<String, Object?> toMap() => {'monthlyFixedPaise': monthlyFixedPaise, 'perTripCostPaise': perTripCostPaise};
}

/// One platform commission line, as a positive amount.
typedef CommissionLine = ({DateTime at, int paise});

/// What one delivered trip earns and what the platform keeps over a period.
/// Revenue is the commission RECORDED in the driver ledger (no money moves
/// through LoadGo yet), so it is a record of what is owed, not cash received.
/// All paise, integer maths, half down.
class UnitEconomics {
  final int days;
  final int trips;
  final int bookings;
  final int cancelled;
  final int deliveredValuePaise;
  final int revenuePaise;
  final EconomicsCosts costs;

  const UnitEconomics({
    required this.days,
    required this.trips,
    required this.bookings,
    required this.cancelled,
    required this.deliveredValuePaise,
    required this.revenuePaise,
    required this.costs,
  });

  int? get avgFarePaise => trips == 0 ? null : deliveredValuePaise ~/ trips;
  int? get revenuePerTripPaise => trips == 0 ? null : revenuePaise ~/ trips;

  /// Revenue as basis points of the delivered value (100 = 1%).
  int? get takeRateBp => deliveredValuePaise == 0 ? null : revenuePaise * 10000 ~/ deliveredValuePaise;

  num? get cancelRate => bookings == 0 ? null : cancelled / bookings;

  /// Revenue per trip minus the cost of serving a trip.
  int? get contributionPerTripPaise => revenuePerTripPaise == null ? null : revenuePerTripPaise! - costs.perTripCostPaise;

  /// Period result: revenue minus per-trip costs minus fixed costs.
  int get profitPaise => revenuePaise - trips * costs.perTripCostPaise - costs.monthlyFixedPaise;

  /// Delivered trips per 30 days needed to cover the fixed cost; null when a
  /// trip does not earn more than it costs (or there is no data).
  int? get breakEvenTrips {
    final c = contributionPerTripPaise;
    if (c == null || c <= 0) return null;
    return (costs.monthlyFixedPaise + c - 1) ~/ c;
  }

  factory UnitEconomics.compute(
    Iterable<Booking> bookings,
    Iterable<CommissionLine> commissions, {
    required EconomicsCosts costs,
    required DateTime now,
    int days = 30,
  }) {
    final t = AdminTrends.from(bookings, now: now, days: days);
    final today = AdminTrends.dayOf(now);
    final first = today.subtract(Duration(days: days - 1));
    var revenue = 0;
    for (final c in commissions) {
      final d = AdminTrends.dayOf(c.at);
      if (!d.isBefore(first) && !d.isAfter(today) && c.paise > 0) revenue += c.paise;
    }
    return UnitEconomics(
      days: days,
      trips: t.delivered,
      bookings: t.bookings,
      cancelled: t.cancelled,
      deliveredValuePaise: t.deliveredPaise,
      revenuePaise: revenue,
      costs: costs,
    );
  }
}
