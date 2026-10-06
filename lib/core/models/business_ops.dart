import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import 'booking.dart';
import 'earnings.dart';

/// Kinds of company expense outside the freight bills (BIZ10).
class BizExpenseKind {
  BizExpenseKind._();
  static const fuel = 'fuel';
  static const toll = 'toll';
  static const loading = 'loading';
  static const detention = 'detention';
  static const other = 'other';
  static const all = [fuel, toll, loading, detention, other];
}

/// `business_expenses/{id}`.
class BizExpense {
  final String id;
  final String kind;
  final int amountPaise;
  final DateTime date;
  final String costCenter;
  final String note;
  const BizExpense({required this.id, required this.kind, required this.amountPaise, required this.date, this.costCenter = '', this.note = ''});

  factory BizExpense.fromDoc(String id, Map<String, dynamic> d) => BizExpense(
        id: id,
        kind: d['kind'] as String? ?? BizExpenseKind.other,
        amountPaise: (d['amountPaise'] as num?)?.round() ?? 0,
        date: (d['date'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
        costCenter: d['costCenter'] as String? ?? '',
        note: d['note'] as String? ?? '',
      );
}

/// Spend of one month: freight (delivered bookings of the company) plus the
/// recorded expenses by kind. Integer paise.
class SpendMonth {
  final String month;
  final int freightPaise;
  final Map<String, int> byKind;
  const SpendMonth({required this.month, required this.freightPaise, required this.byKind});

  int get otherPaise => byKind.values.fold(0, (a, b) => a + b);
  int get totalPaise => freightPaise + otherPaise;
}

/// The expense dashboard (BIZ10): the last [months] months ending at [now],
/// oldest first, each with freight and recorded costs.
List<SpendMonth> spendDashboard(Iterable<Booking> bookings, Iterable<BizExpense> expenses, DateTime now, {int months = 6}) {
  final keys = <String>[];
  for (var i = months - 1; i >= 0; i--) {
    final d = DateTime(now.year, now.month - i);
    keys.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
  }
  String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  final freight = {for (final k in keys) k: 0};
  for (final b in bookings) {
    if (b.status != BookingStatus.delivered) continue;
    final k = key(EarningsSummary.deliveredAt(b));
    if (freight.containsKey(k)) freight[k] = freight[k]! + (b.billAmountPaise ?? 0);
  }
  final kinds = {for (final k in keys) k: <String, int>{}};
  for (final e in expenses) {
    final k = key(e.date);
    if (kinds.containsKey(k)) kinds[k]!.update(e.kind, (v) => v + e.amountPaise, ifAbsent: () => e.amountPaise);
  }
  return [for (final k in keys) SpendMonth(month: k, freightPaise: freight[k]!, byKind: kinds[k]!)];
}

/// `business_contracts/{id}`: a vehicle the company hires on contract.
class ContractVehicle {
  final String id;
  final String vehicleNumber;
  final String vehicleType;
  final String vendorName;
  final int? ratePerTripPaise;
  final DateTime? validUntil;
  final String note;
  const ContractVehicle({required this.id, required this.vehicleNumber, required this.vehicleType, required this.vendorName, this.ratePerTripPaise, this.validUntil, this.note = ''});

  factory ContractVehicle.fromDoc(String id, Map<String, dynamic> d) => ContractVehicle(
        id: id,
        vehicleNumber: d['vehicleNumber'] as String? ?? '',
        vehicleType: d['vehicleType'] as String? ?? '',
        vendorName: d['vendorName'] as String? ?? '',
        ratePerTripPaise: (d['ratePerTripPaise'] as num?)?.round(),
        validUntil: (d['validUntil'] as Timestamp?)?.toDate(),
        note: d['note'] as String? ?? '',
      );

  bool expired(DateTime now) => validUntil != null && validUntil!.isBefore(now);
}

/// `business_pool/{ownerId}_{driverId}`: an approved driver.
class PoolDriver {
  final String driverId;
  final String name;
  final String vehicleNumber;
  const PoolDriver({required this.driverId, required this.name, this.vehicleNumber = ''});

  factory PoolDriver.fromDoc(Map<String, dynamic> d) => PoolDriver(
        driverId: d['driverId'] as String? ?? '',
        name: d['driverName'] as String? ?? '',
        vehicleNumber: d['vehicleNumber'] as String? ?? '',
      );
}
