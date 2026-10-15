import '../money/money.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import 'booking.dart';
import 'ledger_entry.dart';

/// `payouts/{id}`: a driver asks LoadGo to pay out money from their wallet.
/// Record only: an admin pays by hand outside the app and marks it paid.
/// LATER(paid): bank payout API, payout verification (PAY10).
class Payout {
  final String id;
  final String driverId;
  final int amountPaise;
  final String status;
  final DateTime? createdAt;

  /// Who approved (maker) and who paid (checker), and the bank or UPI reference. Null until then.
  final String? approvedBy;
  final String? paidBy;
  final String? reference;

  const Payout({
    required this.id,
    required this.driverId,
    required this.amountPaise,
    required this.status,
    this.createdAt,
    this.approvedBy,
    this.paidBy,
    this.reference,
  });

  static const requested = 'requested';
  static const approved = 'approved';
  static const paid = 'paid';
  static const rejected = 'rejected';

  /// A paid payout that came back (the transfer failed).
  static const reversed = 'reversed';

  /// Statuses in the order a payout normally moves.
  static const all = [requested, approved, paid, rejected, reversed];

  /// The money is held for this payout: asked for or approved, not yet paid.
  bool get isOpen => status == requested || status == approved;

  /// Smallest and largest request, in paise (Rs 1 to Rs 10,00,000).
  static const minPaise = 100;
  static const maxPaise = 100000000;

  factory Payout.fromDoc(String id, Map<String, dynamic> d) => Payout(
        id: id,
        driverId: d['driverId'] is String ? d['driverId'] as String : '',
        amountPaise: Money.parse(d['amountPaise']).paise,
        status: all.contains(d['status']) ? d['status'] as String : requested,
        createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null,
        approvedBy: d['approvedBy'] is String ? d['approvedBy'] as String : null,
        paidBy: d['paidBy'] is String ? d['paidBy'] as String : null,
        reference: d['reference'] is String ? d['reference'] as String : null,
      );
}

/// The four wallet figures a driver cares about (paise).
class WalletBalances {
  /// Delivered trips whose payment the driver has not confirmed yet.
  final int pending;

  /// Confirmed earnings minus commission (the old "net").
  final int net;

  /// Payout requests waiting for LoadGo.
  final int requested;

  /// Payouts LoadGo has paid.
  final int paidOut;

  const WalletBalances({required this.pending, required this.net, required this.requested, required this.paidOut});

  /// What can still be requested: net minus money already requested or paid.
  int get available {
    final a = net - requested - paidOut;
    return a < 0 ? 0 : a;
  }

  factory WalletBalances.of({
    required Iterable<LedgerEntry> ledger,
    required Iterable<Booking> bookings,
    required Iterable<Payout> payouts,
  }) {
    final sum = WalletSummary.of(ledger);
    var pending = 0;
    for (final b in bookings) {
      if (b.status == BookingStatus.delivered && b.paymentStatus != PaymentStatus.driverConfirmed) {
        pending += b.billAmountPaise ?? 0;
      }
    }
    int total(bool Function(Payout) test) => payouts.where(test).fold(0, (a, p) => a + p.amountPaise);
    // Approved payouts are still waiting for payment: they stay in "requested".
    return WalletBalances(pending: pending, net: sum.net, requested: total((p) => p.isOpen), paidOut: total((p) => p.status == Payout.paid));
  }
}
