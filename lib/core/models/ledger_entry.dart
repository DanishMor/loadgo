import 'package:cloud_firestore/cloud_firestore.dart';

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
    final d = doc.data() ?? const {};
    return LedgerEntry(
      id: doc.id,
      driverId: d['driverId'] as String? ?? '',
      bookingId: d['bookingId'] as String? ?? '',
      type: d['type'] as String? ?? '',
      amountPaise: (d['amountPaise'] as num?)?.round() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Totals over a driver's ledger.
class WalletSummary {
  final int earnings;
  final int commission;
  const WalletSummary(this.earnings, this.commission);

  int get net => earnings + commission;

  factory WalletSummary.of(Iterable<LedgerEntry> entries) {
    var e = 0, c = 0;
    for (final x in entries) {
      if (x.type == LedgerType.tripEarning) e += x.amountPaise;
      if (x.type == LedgerType.platformCommission) c += x.amountPaise;
    }
    return WalletSummary(e, c);
  }
}
