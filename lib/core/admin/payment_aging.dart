import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Who is slow with a payment record on a delivered trip (MASTER-6 Task 8).
/// Payments are records only, so "unpaid" means: the customer has not marked
/// the trip paid, or the driver has not confirmed receiving it.
class AgingRow {
  final String bookingId;

  /// Who has to act: `customer` (mark paid) or `driver` (confirm received).
  final String waitingOn;
  final String userId;
  final int ageDays;
  final int amountPaise;
  const AgingRow({required this.bookingId, required this.waitingOn, required this.userId, required this.ageDays, required this.amountPaise});

  String get bucket => PaymentAging.bucketOf(ageDays);
}

class PaymentAging {
  PaymentAging._();

  static const buckets = ['d0', 'd1', 'd3', 'd7'];

  /// 0-1 days, 2-3, 4-7, over 7.
  static String bucketOf(int days) => days <= 1 ? 'd0' : days <= 3 ? 'd1' : days <= 7 ? 'd3' : 'd7';

  /// A person can be nudged again only after this many hours (the rules check the same).
  static const nudgeCooldownHours = 6;

  static DateTime? _t(Object? v) => v is Timestamp ? v.toDate() : null;

  /// Rows for delivered bookings whose payment is not confirmed yet, oldest
  /// first. The age counts from the delivery (customer to act) or from when
  /// the customer marked it paid (driver to act).
  static List<AgingRow> compute(Iterable<(String, Map<String, dynamic>)> bookings, DateTime now) {
    final rows = <AgingRow>[];
    for (final (id, d) in bookings) {
      if (d['status'] != 'delivered') continue;
      final pay = d['paymentStatus'] ?? 'pending';
      if (pay == 'driver_confirmed') continue;
      final timeline = d['timeline'] is Map ? d['timeline'] as Map : const {};
      final from = pay == 'customer_marked_paid' ? (_t(d['paymentMarkedAt']) ?? _t(timeline['delivered'])) : _t(timeline['delivered']);
      if (from == null) continue; // no time to age from
      final amount = ((d['paidAmountPaise'] ?? d['agreedFarePaise'] ?? d['fareEstimate'] ?? 0) as num).round();
      final waitingOn = pay == 'customer_marked_paid' ? 'driver' : 'customer';
      rows.add(AgingRow(
        bookingId: id,
        waitingOn: waitingOn,
        userId: '${waitingOn == 'driver' ? d['driverId'] ?? '' : d['customerId'] ?? ''}',
        ageDays: now.difference(from).inDays.clamp(0, 100000),
        amountPaise: amount,
      ));
    }
    rows.sort((a, b) => b.ageDays.compareTo(a.ageDays));
    return rows;
  }

  static Map<String, int> countByBucket(Iterable<AgingRow> rows) {
    final out = {for (final b in buckets) b: 0};
    for (final r in rows) {
      out[r.bucket] = out[r.bucket]! + 1;
    }
    return out;
  }

  static String nudgeId(String bookingId, String target) => '${bookingId}_$target';
}
