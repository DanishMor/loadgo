import 'package:cloud_firestore/cloud_firestore.dart';

/// What an expense was for.
class ExpenseKind {
  ExpenseKind._();
  static const fuel = 'fuel';
  static const toll = 'toll';
  static const repair = 'repair';
  static const service = 'service';
  static const other = 'other';
  static const all = [fuel, toll, repair, service, other];
}

/// `vehicle_expenses/{id}`: one fuel / toll / repair line of a vehicle, in
/// integer paise. A record for the owner's own books (V10).
class VehicleExpense {
  static const maxPaise = 10000000; // Rs 1,00,000 per line

  final String id;
  final String ownerId;
  final String vehicleId;
  final String kind;
  final int amountPaise;
  final String note;
  final DateTime date;

  const VehicleExpense({required this.id, required this.ownerId, required this.vehicleId, required this.kind, required this.amountPaise, this.note = '', required this.date});

  factory VehicleExpense.fromDoc(String id, Map<String, dynamic> d) => VehicleExpense(
        id: id,
        ownerId: d['ownerId'] as String? ?? '',
        vehicleId: d['vehicleId'] as String? ?? '',
        kind: ExpenseKind.all.contains(d['kind']) ? d['kind'] as String : ExpenseKind.other,
        amountPaise: (d['amountPaise'] as num?)?.round() ?? 0,
        note: d['note'] as String? ?? '',
        date: (d['date'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Totals of a list of expenses (pure).
class ExpenseSummary {
  ExpenseSummary._();

  static int total(Iterable<VehicleExpense> e) => e.fold(0, (a, x) => a + x.amountPaise);

  /// `yyyy-MM` -> paise, newest month first.
  static Map<String, int> byMonth(Iterable<VehicleExpense> e) {
    final m = <String, int>{};
    for (final x in e) {
      final k = '${x.date.year}-${x.date.month.toString().padLeft(2, '0')}';
      m[k] = (m[k] ?? 0) + x.amountPaise;
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.key.compareTo(a.key)));
  }

  static Map<String, int> byKind(Iterable<VehicleExpense> e) {
    final m = <String, int>{};
    for (final x in e) {
      m[x.kind] = (m[x.kind] ?? 0) + x.amountPaise;
    }
    return m;
  }

  /// Expenses dated within the last [days] days up to [now].
  static List<VehicleExpense> lastDays(Iterable<VehicleExpense> e, DateTime now, int days) {
    final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    return [for (final x in e) if (!x.date.isBefore(from) && !x.date.isAfter(now.add(const Duration(days: 1)))) x];
  }
}
