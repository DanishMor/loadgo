import 'package:flutter/material.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/ledger_entry.dart';
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
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
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

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    if (b.status == BookingStatus.cancelled) return const SizedBox.shrink();
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
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
              ),
              StatusChip(label: paymentStatusLabel(context, b.paymentStatus), color: color),
            ],
          ),
          if (b.paidAmountPaise != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(formatPaise(b.paidAmountPaise!),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.title)),
            ),
          const SizedBox(height: 8),
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
          Text(tr(context, 'recordsOnly'), style: const TextStyle(fontSize: 12, color: AppColors.faint)),
        ],
      ),
    );
  }
}
