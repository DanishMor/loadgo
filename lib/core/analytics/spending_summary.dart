import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/earnings.dart';
import 'trip_stats.dart';

/// "2026-10" for [d] (local).
String monthKeyOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

class SpendLine {
  /// Cargo type or "Delhi → Jaipur".
  final String label;
  final int paise;
  final int trips;
  const SpendLine(this.label, this.paise, this.trips);
}

class MonthSpend {
  /// `yyyy-MM`.
  final String key;
  final int paise;
  final int trips;
  const MonthSpend(this.key, this.paise, this.trips);
}

/// One month in detail.
class MonthSpending {
  final String key;
  final int totalPaise;
  final int trips;
  final List<SpendLine> byCargo;
  final List<SpendLine> byRoute;
  const MonthSpending({required this.key, required this.totalPaise, required this.trips, required this.byCargo, required this.byRoute});

  bool get isEmpty => trips == 0;
}

/// What a customer paid for delivered trips (integer paise, billed amount),
/// by month, cargo and route. Only delivered bookings count: a cancelled one
/// was never paid for.
class SpendingSummary {
  /// The latest months, oldest first, the last one is the month of `now`.
  final List<MonthSpend> months;
  final int totalPaise;
  final int trips;
  final List<Booking> _delivered;

  const SpendingSummary._(this.months, this.totalPaise, this.trips, this._delivered);

  factory SpendingSummary.from(Iterable<Booking> bookings, DateTime now, {int months = 6}) {
    final keys = [for (var i = months - 1; i >= 0; i--) monthKeyOf(DateTime(now.year, now.month - i))];
    final paise = {for (final k in keys) k: 0};
    final count = {for (final k in keys) k: 0};
    final delivered = <Booking>[];
    var total = 0;
    for (final b in bookings) {
      if (b.status != BookingStatus.delivered) continue;
      delivered.add(b);
      final p = b.billAmountPaise ?? 0;
      total += p;
      final k = monthKeyOf(EarningsSummary.deliveredAt(b));
      if (paise.containsKey(k)) {
        paise[k] = paise[k]! + p;
        count[k] = count[k]! + 1;
      }
    }
    return SpendingSummary._([for (final k in keys) MonthSpend(k, paise[k]!, count[k]!)], total, delivered.length, delivered);
  }

  List<SpendLine> _group(Iterable<Booking> list, String Function(Booking) label) {
    final paise = <String, int>{};
    final count = <String, int>{};
    for (final b in list) {
      final l = label(b);
      paise[l] = (paise[l] ?? 0) + (b.billAmountPaise ?? 0);
      count[l] = (count[l] ?? 0) + 1;
    }
    final out = [for (final e in paise.entries) SpendLine(e.key, e.value, count[e.key]!)];
    out.sort((a, b) {
      final c = b.paise.compareTo(a.paise);
      return c != 0 ? c : a.label.compareTo(b.label);
    });
    return out;
  }

  /// Totals, cargo lines and route lines of the month [key] (`yyyy-MM`),
  /// biggest first (ties by name). Works for any month, not only the listed ones.
  MonthSpending forMonth(String key) {
    final inMonth = _delivered.where((b) => monthKeyOf(EarningsSummary.deliveredAt(b)) == key).toList();
    return MonthSpending(
      key: key,
      totalPaise: inMonth.fold(0, (s, b) => s + (b.billAmountPaise ?? 0)),
      trips: inMonth.length,
      byCargo: _group(inMonth, (b) => b.cargoType.trim().isEmpty ? '-' : b.cargoType.trim()),
      byRoute: _group(inMonth, (b) => routeKey(b.pickup, b.drop)),
    );
  }

  int get peakMonthPaise => months.fold(0, (m, e) => e.paise > m ? e.paise : m);
}
