import '../constants/cancel_reasons.dart';
import 'admin_export.dart';

/// Weekly cohorts of loads (MASTER-6 Task 6): how fast a load gets its first
/// bid and its driver, how many customers come back, and why trips are
/// cancelled. A cohort is the Monday-start week the load was posted in.
class CohortLoad {
  final String id;
  final String shipperId;
  final DateTime createdAt;
  const CohortLoad(this.id, this.shipperId, this.createdAt);
}

class CohortOffer {
  final String loadId;
  final DateTime createdAt;
  const CohortOffer(this.loadId, this.createdAt);
}

class CohortBooking {
  final String loadId;
  final DateTime createdAt;
  final String status;
  final String? cancelReason;
  const CohortBooking(this.loadId, this.createdAt, this.status, [this.cancelReason]);
}

class CohortRow {
  final DateTime week;
  final int loads;
  final int withBid;
  final int filled;

  /// Median minutes from posting to the first bid / to the booking; null when none.
  final int? medianFirstBidMinutes;
  final int? medianFillMinutes;
  final int customers;
  final int repeatCustomers;

  /// Cancelled bookings of this cohort by reason code (`none` = no reason given).
  final Map<String, int> cancelReasons;

  const CohortRow({
    required this.week,
    required this.loads,
    required this.withBid,
    required this.filled,
    required this.medianFirstBidMinutes,
    required this.medianFillMinutes,
    required this.customers,
    required this.repeatCustomers,
    required this.cancelReasons,
  });

  int? get repeatPercent => customers == 0 ? null : repeatCustomers * 100 ~/ customers;
}

class PilotCohorts {
  PilotCohorts._();

  static const noReason = 'none';

  /// Monday 00:00 of the week containing [t].
  static DateTime weekStart(DateTime t) => DateTime(t.year, t.month, t.day - (t.weekday - 1));

  static int? median(List<int> v) {
    if (v.isEmpty) return null;
    final s = [...v]..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) ~/ 2;
  }

  /// Newest week first. Minutes are never negative (a clock skew counts as 0).
  static List<CohortRow> compute(Iterable<CohortLoad> loads, Iterable<CohortOffer> offers, Iterable<CohortBooking> bookings) {
    final firstBid = <String, DateTime>{};
    for (final o in offers) {
      final old = firstBid[o.loadId];
      if (old == null || o.createdAt.isBefore(old)) firstBid[o.loadId] = o.createdAt;
    }
    final booking = <String, CohortBooking>{};
    final cancelled = <String, List<CohortBooking>>{};
    for (final b in bookings) {
      if (b.status == 'cancelled') {
        (cancelled[b.loadId] ??= []).add(b);
      } else {
        final old = booking[b.loadId];
        if (old == null || b.createdAt.isBefore(old.createdAt)) booking[b.loadId] = b;
      }
    }
    final weeksOf = <String, Set<DateTime>>{}; // customer -> weeks they posted in
    for (final l in loads) {
      (weeksOf[l.shipperId] ??= {}).add(weekStart(l.createdAt));
    }
    final byWeek = <DateTime, List<CohortLoad>>{};
    for (final l in loads) {
      (byWeek[weekStart(l.createdAt)] ??= []).add(l);
    }
    int minutes(DateTime from, DateTime to) => to.difference(from).inMinutes.clamp(0, 1 << 30);
    final rows = <CohortRow>[];
    for (final e in byWeek.entries) {
      final bidMinutes = <int>[];
      final fillMinutes = <int>[];
      final reasons = <String, int>{};
      var filled = 0;
      for (final l in e.value) {
        final fb = firstBid[l.id];
        if (fb != null) bidMinutes.add(minutes(l.createdAt, fb));
        final b = booking[l.id];
        if (b != null) {
          filled++;
          fillMinutes.add(minutes(l.createdAt, b.createdAt));
        }
        for (final c in cancelled[l.id] ?? const <CohortBooking>[]) {
          final r = c.cancelReason;
          final key = r != null && (CancelReasons.customer.contains(r) || CancelReasons.driver.contains(r)) ? r : noReason;
          reasons[key] = (reasons[key] ?? 0) + 1;
        }
      }
      final people = {for (final l in e.value) l.shipperId};
      rows.add(CohortRow(
        week: e.key,
        loads: e.value.length,
        withBid: bidMinutes.length,
        filled: filled,
        medianFirstBidMinutes: median(bidMinutes),
        medianFillMinutes: median(fillMinutes),
        customers: people.length,
        repeatCustomers: people.where((p) => weeksOf[p]!.length > 1).length,
        cancelReasons: reasons,
      ));
    }
    rows.sort((a, b) => b.week.compareTo(a.week));
    return rows;
  }

  static String _d(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  /// CSV: one row per week; counts and minutes only.
  static String toCsv(List<CohortRow> rows) {
    final codes = [...{...CancelReasons.customer, ...CancelReasons.driver}, noReason];
    final head = ['week', 'loads', 'with_bid', 'filled', 'median_first_bid_min', 'median_fill_min', 'customers', 'repeat_customers', 'repeat_percent', for (final c in codes) 'cancel_$c'];
    final lines = [head.join(',')];
    for (final r in rows) {
      lines.add([
        _d(r.week),
        r.loads,
        r.withBid,
        r.filled,
        r.medianFirstBidMinutes ?? '',
        r.medianFillMinutes ?? '',
        r.customers,
        r.repeatCustomers,
        r.repeatPercent ?? '',
        for (final c in codes) r.cancelReasons[c] ?? 0,
      ].map(AdminExport.cell).join(','));
    }
    return lines.join('\n');
  }
}
