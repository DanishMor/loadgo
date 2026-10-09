import '../models/booking.dart';
import '../models/ledger_entry.dart';
import 'payment_timeline.dart';

/// A delivered trip whose money is not in the wallet yet.
class WaitingTrip {
  final Booking booking;

  /// [PaymentNext.waitCustomer] (the customer has not marked it paid) or
  /// [PaymentNext.confirmReceived] (the driver has to confirm).
  final PaymentNext next;

  /// What the trip is worth (paise), 0 when unknown.
  final int amountPaise;
  const WaitingTrip(this.booking, this.next, this.amountPaise);
}

/// Plain facts for the wallet screen (MASTER-6 Task 25).
class WalletInsight {
  WalletInsight._();

  /// Delivered trips not yet confirmed received, those waiting on the driver
  /// first, then the oldest delivery first.
  static List<WaitingTrip> waiting(Iterable<Booking> bookings) {
    final out = <WaitingTrip>[];
    for (final b in bookings) {
      final t = PaymentTimeline.of(b);
      if (t.next != PaymentNext.waitCustomer && t.next != PaymentNext.confirmReceived) continue;
      out.add(WaitingTrip(b, t.next, b.billAmountPaise ?? 0));
    }
    int rank(WaitingTrip w) => w.next == PaymentNext.confirmReceived ? 0 : 1;
    DateTime at(WaitingTrip w) => w.booking.timeline['delivered'] ?? DateTime(2100);
    out.sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : at(a).compareTo(at(b)));
    return out;
  }

  /// Total of [waiting] trips with a known amount.
  static int waitingTotal(Iterable<WaitingTrip> w) => w.fold(0, (a, b) => a + b.amountPaise);

  /// The commission of a booking as a whole percent of its earning, or null
  /// when either line is missing or the earning is not positive.
  static int? commissionPercent(Iterable<LedgerEntry> entries, String bookingId) {
    int? earning, commission;
    for (final e in entries) {
      if (e.bookingId != bookingId) continue;
      if (e.type == LedgerType.tripEarning) earning = e.amountPaise;
      if (e.type == LedgerType.platformCommission) commission = -e.amountPaise;
    }
    if (earning == null || commission == null || earning <= 0 || commission < 0) return null;
    return (commission * 100 / earning).round();
  }
}
