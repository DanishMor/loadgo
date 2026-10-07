import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/ledger_entry.dart';

/// One step of "when do I get my money" for a trip.
enum PaymentStep { delivered, customerPaid, driverConfirmed, inWallet }

class PaymentStepInfo {
  final PaymentStep step;
  final bool done;

  /// When it happened, if the app recorded it.
  final DateTime? at;

  /// Money tied to the step (paise): customer's amount, or what lands in the wallet.
  final int? paise;
  const PaymentStepInfo(this.step, {required this.done, this.at, this.paise});
}

/// The next thing that has to happen, as a translation key.
enum PaymentNext { finishTrip, waitCustomer, confirmReceived, nothing }

/// A driver's payment timeline for one trip. Pure. Payments are RECORDS (no
/// money moves through LoadGo): the customer marks the trip paid, the driver
/// confirms it, and the ledger then holds the earning and the commission.
class PaymentTimeline {
  final List<PaymentStepInfo> steps;
  final PaymentNext next;

  /// Commission kept by the platform (positive paise), when recorded.
  final int? commissionPaise;

  const PaymentTimeline({required this.steps, required this.next, this.commissionPaise});

  bool get complete => steps.every((s) => s.done);

  /// [earning] and [commission] are the booking's ledger lines (null until the
  /// driver confirmed the payment).
  factory PaymentTimeline.of(Booking b, {LedgerEntry? earning, LedgerEntry? commission}) {
    final delivered = b.status == BookingStatus.delivered;
    final paid = b.paymentStatus == PaymentStatus.customerMarkedPaid || b.paymentStatus == PaymentStatus.driverConfirmed;
    final confirmed = b.paymentStatus == PaymentStatus.driverConfirmed;
    final commissionPaise = commission == null ? null : -commission.amountPaise;
    final net = earning == null ? null : earning.amountPaise - (commissionPaise ?? 0);
    return PaymentTimeline(
      commissionPaise: commissionPaise,
      steps: [
        PaymentStepInfo(PaymentStep.delivered, done: delivered, at: b.timeline[BookingStatus.delivered]),
        PaymentStepInfo(PaymentStep.customerPaid, done: paid, paise: b.paidAmountPaise),
        PaymentStepInfo(PaymentStep.driverConfirmed, done: confirmed, at: earning?.createdAt),
        PaymentStepInfo(PaymentStep.inWallet, done: confirmed && earning != null, at: earning?.createdAt, paise: net),
      ],
      next: !delivered
          ? PaymentNext.finishTrip
          : !paid
              ? PaymentNext.waitCustomer
              : !confirmed
                  ? PaymentNext.confirmReceived
                  : PaymentNext.nothing,
    );
  }
}
