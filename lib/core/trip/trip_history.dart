import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/earnings.dart';

/// Status groups of the history filter.
enum HistoryStatus { delivered, cancelled, active }

/// Which date a booking sits at in the history: delivery day for a delivered
/// one, cancel day for a cancelled one (its `cancelled` step, else booking
/// time), otherwise the booking time.
DateTime historyDate(Booking b) {
  if (b.status == BookingStatus.delivered) return EarningsSummary.deliveredAt(b);
  if (b.status == BookingStatus.cancelled) return b.timeline[BookingStatus.cancelled] ?? b.createdAt?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
  return b.createdAt?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
}

HistoryStatus historyStatusOf(Booking b) => switch (b.status) {
      BookingStatus.delivered => HistoryStatus.delivered,
      BookingStatus.cancelled => HistoryStatus.cancelled,
      _ => HistoryStatus.active,
    };

/// Filter of a trip history: status groups, an inclusive date range (whole
/// days) and vehicle numbers. An empty set means "no limit".
class TripHistoryFilter {
  final Set<HistoryStatus> statuses;
  final DateTime? from;
  final DateTime? to;
  final Set<String> vehicles;

  const TripHistoryFilter({this.statuses = const {}, this.from, this.to, this.vehicles = const {}});

  bool get isEmpty => statuses.isEmpty && from == null && to == null && vehicles.isEmpty;

  TripHistoryFilter copyWith({
    Set<HistoryStatus>? statuses,
    Object? from = _keep,
    Object? to = _keep,
    Set<String>? vehicles,
  }) =>
      TripHistoryFilter(
        statuses: statuses ?? this.statuses,
        from: identical(from, _keep) ? this.from : from as DateTime?,
        to: identical(to, _keep) ? this.to : to as DateTime?,
        vehicles: vehicles ?? this.vehicles,
      );

  static const _keep = Object();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  bool matches(Booking b) {
    if (statuses.isNotEmpty && !statuses.contains(historyStatusOf(b))) return false;
    if (vehicles.isNotEmpty && !vehicles.contains(b.vehicleNumber)) return false;
    final d = _day(historyDate(b));
    if (from != null && d.isBefore(_day(from!))) return false;
    if (to != null && d.isAfter(_day(to!))) return false;
    return true;
  }

  /// Matching bookings, newest first.
  List<Booking> apply(Iterable<Booking> all) {
    final out = all.where(matches).toList()..sort((a, b) => historyDate(b).compareTo(historyDate(a)));
    return out;
  }

  /// Vehicle numbers seen in [all] (sorted, without blanks).
  static List<String> vehicleNumbers(Iterable<Booking> all) => ({for (final b in all) b.vehicleNumber.trim()}..remove('')).toList()..sort();

  static String _cell(String s) => (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;

  static String _rupees(int paise) {
    final p = paise.abs();
    final s = '${p ~/ 100}.${(p % 100).toString().padLeft(2, '0')}';
    return paise < 0 ? '-$s' : s;
  }

  /// `date,status,pickup,drop,cargo,vehicle,amount_rupees` (text cells quoted when needed).
  static String toCsv(Iterable<Booking> list) {
    final rows = ['date,status,pickup,drop,cargo,vehicle,amount_rupees'];
    for (final b in list) {
      final d = historyDate(b);
      final date = d.millisecondsSinceEpoch == 0 ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      rows.add([
        date,
        b.status,
        _cell(b.pickup),
        _cell(b.drop),
        _cell(b.cargoType),
        _cell(b.vehicleNumber),
        b.billAmountPaise == null ? '' : _rupees(b.billAmountPaise!),
      ].join(','));
    }
    return rows.join('\n');
  }
}
