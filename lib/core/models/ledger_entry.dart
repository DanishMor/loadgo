import 'package:cloud_firestore/cloud_firestore.dart';

import '../money/money.dart';

/// Payment mode chosen on the load. Must stay in sync with firestore.rules.
class PaymentMode {
  PaymentMode._();
  static const cash = 'cash';
  static const upiDirect = 'upi_direct';
  static const all = [cash, upiDirect];
}

/// Booking payment record (no money moves through LoadGo yet).
/// LATER(paid): payment gateway / escrow.
class PaymentStatus {
  PaymentStatus._();
  static const pending = 'pending';
  static const customerMarkedPaid = 'customer_marked_paid';
  static const driverConfirmed = 'driver_confirmed';
}

class LedgerType {
  LedgerType._();
  static const tripEarning = 'trip_earning';
  static const platformCommission = 'platform_commission';

  /// A signed correction by finance or super, with a reason (F8).
  static const adjustment = 'adjustment';
}

/// `ledger/{bookingId}_{type}`: append-only driver wallet line (paise).
/// Commission lines are negative.
class LedgerEntry {
  final String id;
  final String driverId;
  final String bookingId;
  final String type;
  final int amountPaise;
  final DateTime? createdAt;

  const LedgerEntry({
    required this.id,
    required this.driverId,
    required this.bookingId,
    required this.type,
    required this.amountPaise,
    this.createdAt,
  });

  factory LedgerEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    // Defensive (F10): a missing field, a wrong type, NaN or a huge number in an
    // old or damaged document becomes an empty value, never an exception.
    final d = doc.data() ?? const {};
    String text(String k) => d[k] is String ? d[k] as String : '';
    return LedgerEntry(
      id: doc.id,
      driverId: text('driverId'),
      bookingId: text('bookingId'),
      type: text('type'),
      amountPaise: Money.parse(d['amountPaise']).paise,
      createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null,
    );
  }
}

/// Totals over a driver's ledger.
class WalletSummary {
  final int earnings;
  final int commission;

  /// Admin corrections (signed).
  final int adjustments;
  const WalletSummary(this.earnings, this.commission, [this.adjustments = 0]);

  int get net => earnings + commission + adjustments;

  factory WalletSummary.of(Iterable<LedgerEntry> entries) {
    var e = 0, c = 0, a = 0;
    for (final x in entries) {
      if (x.type == LedgerType.tripEarning) e += x.amountPaise;
      if (x.type == LedgerType.platformCommission) c += x.amountPaise;
      if (x.type == LedgerType.adjustment) a += x.amountPaise;
    }
    return WalletSummary(e, c, a);
  }
}
