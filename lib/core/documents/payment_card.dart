import '../errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/ledger_entry.dart';
import '../payments/payment_logic.dart';
import '../services/backend.dart';
import '../services/payment_service.dart';
import '../widgets/common.dart';
import '../widgets/logistics_labels.dart';

String paymentModeLabel(BuildContext context, String mode) =>
    tr(context, mode == PaymentMode.upiDirect ? 'payUpiDirect' : 'payCash');

String paymentStatusLabel(BuildContext context, String status) => tr(context, switch (status) {
      PaymentStatus.customerMarkedPaid => 'payMarked',
      PaymentStatus.driverConfirmed => 'payConfirmed',
      _ => 'payPending',
    });

/// Payment record for a booking: mode, status, amount, and the next action
/// for whoever is looking (customer marks paid, driver confirms). Records only.
class PaymentCard extends StatefulWidget {
  final Booking booking;
  const PaymentCard({super.key, required this.booking});

  @override
  State<PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<PaymentCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markPaid() async {
    final b = widget.booking;
    final paise = await askPricePaise(context,
        title: tr(context, 'markPaid'), label: tr(context, 'amountPaid'), initialPaise: b.billAmountPaise, note: tr(context, 'recordsOnly'));
    if (paise != null) await _run(() => PaymentService.markPaid(b, paise));
  }

  Future<void> _recordAdvance() async {
    final b = widget.booking;
    final paise = await askPricePaise(context, title: tr(context, 'advanceRecord'), label: tr(context, 'advanceAmountLabel'), initialPaise: null, note: tr(context, 'recordsOnly'));
    if (paise == null || !mounted) return;
    if (!validAdvance(paise, b.billAmountPaise)) {
      showSnack(context, tr(context, 'advanceInvalid'));
      return;
    }
    await _run(() => PaymentService.recordAdvance(b, paise));
  }

  /// Opens the customer's UPI app with the driver's id and what is still due.
  Future<void> _payViaUpi() async {
    final b = widget.booking;
    final due = b.advanceConfirmedAt != null && b.advancePaise != null ? (b.billAmountPaise ?? 0) - b.advancePaise! : (b.billAmountPaise ?? 0);
    if (due <= 0) return;
    var ok = false;
    try {
      ok = await launchUrl(upiPayUri(upiId: b.payUpiId, payeeName: b.driverName, amountPaise: due, note: '${b.pickup} to ${b.drop}', ref: b.id), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) showSnack(context, tr(context, 'upiCannotOpen'));
  }

  Future<void> _shareUpi() async {
    try {
      final done = await PaymentService.shareUpiId(widget.booking);
      if (mounted) showSnack(context, tr(context, done ? 'upiIdShared' : 'upiMissing'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    if (b.status == BookingStatus.cancelled) return const SizedBox.shrink();
    final open = b.status != BookingStatus.delivered && b.paymentStatus == PaymentStatus.pending;
    final me = Backend.uid;
    final color = switch (b.paymentStatus) {
      PaymentStatus.driverConfirmed => AppColors.success,
      PaymentStatus.customerMarkedPaid => AppColors.warning,
      _ => AppColors.faint,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${tr(context, 'paymentLabel')} • ${paymentModeLabel(context, b.paymentMode)}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
              ),
              StatusChip(label: paymentStatusLabel(context, b.paymentStatus), color: color),
            ],
          ),
          if (b.paidAmountPaise != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(formatPaise(b.paidAmountPaise!),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.title)),
            ),
          if (b.advancePaise != null && b.billAmountPaise != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                trf(context, 'advanceLine', {'amount': formatPaise(b.advancePaise!), 'balance': formatPaise(AdvanceSummary(advancePaise: b.advancePaise!, totalPaise: b.billAmountPaise!, confirmed: b.advanceConfirmedAt != null).balancePaise)}),
                key: const ValueKey('advanceLine'),
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.body),
              ),
            ),
          if (b.advancePaise != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: b.advanceConfirmedAt != null
                  ? StatusChip(label: tr(context, 'advanceConfirmedChip'), color: AppColors.success)
                  : Text(tr(context, 'advanceWaiting'), key: const ValueKey('advanceWaiting'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          const SizedBox(height: 8),
          if (me == b.customerId && open && b.advancePaise == null)
            OutlinedButton.icon(
              key: const ValueKey('recordAdvance'),
              onPressed: _busy ? null : _recordAdvance,
              icon: const Icon(Icons.savings_outlined),
              label: Text(tr(context, 'advanceRecord')),
            ),
          if (me == b.driverId && b.advancePaise != null && b.advanceConfirmedAt == null)
            FilledButton.tonalIcon(
              key: const ValueKey('confirmAdvance'),
              onPressed: _busy ? null : () => _run(() => PaymentService.confirmAdvance(b)),
              icon: const Icon(Icons.verified_outlined),
              label: Text(tr(context, 'advanceConfirm')),
            ),
          if (me == b.customerId && open && b.payUpiId.isNotEmpty)
            FilledButton.tonalIcon(
              key: const ValueKey('payViaUpi'),
              onPressed: _busy ? null : _payViaUpi,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(tr(context, 'payViaUpi')),
            ),
          if (me == b.driverId && open && b.payUpiId.isEmpty)
            TextButton.icon(
              key: const ValueKey('shareUpi'),
              onPressed: _busy ? null : _shareUpi,
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: Text(tr(context, 'shareUpiId')),
            ),
          if (me == b.customerId && b.paymentStatus == PaymentStatus.pending)
            FilledButton.icon(
              key: const ValueKey('markPaid'),
              onPressed: _busy ? null : _markPaid,
              icon: const Icon(Icons.check_rounded),
              label: Text(tr(context, 'markPaid')),
            ),
          if (me == b.driverId && b.paymentStatus == PaymentStatus.customerMarkedPaid)
            FilledButton.icon(
              key: const ValueKey('confirmReceived'),
              onPressed: _busy ? null : () => _run(() => PaymentService.confirmReceived(b)),
              icon: const Icon(Icons.verified_rounded),
              label: Text(tr(context, 'confirmReceived')),
            ),
          const SizedBox(height: 4),
          Text(tr(context, 'recordsOnly'), style: TextStyle(fontSize: 12, color: AppColors.faint)),
        ],
      ),
    );
  }
}
