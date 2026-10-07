import '../constants/logistics.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/ledger_entry.dart';
import '../services/backend.dart';
import '../widgets/common.dart';
import 'payment_timeline.dart';

/// On the driver's trip screen: four steps from "trip delivered" to "money in
/// my wallet", the amount that lands there and what happens next.
class PaymentTimelineCard extends StatefulWidget {
  final Booking booking;
  const PaymentTimelineCard({super.key, required this.booking});

  @override
  State<PaymentTimelineCard> createState() => _PaymentTimelineCardState();
}

class _PaymentTimelineCardState extends State<PaymentTimelineCard> {
  late Future<(LedgerEntry?, LedgerEntry?)> _lines = _load();

  Future<(LedgerEntry?, LedgerEntry?)> _load() async {
    final b = widget.booking;
    if (b.paymentStatus != PaymentStatus.driverConfirmed) return (null, null);
    final col = Backend.db.collection('ledger');
    try {
      final e = await col.doc('${b.id}_${LedgerType.tripEarning}').get();
      final c = await col.doc('${b.id}_${LedgerType.platformCommission}').get();
      return (e.exists ? LedgerEntry.fromDoc(e) : null, c.exists ? LedgerEntry.fromDoc(c) : null);
    } catch (_) {
      return (null, null);
    }
  }

  @override
  void didUpdateWidget(PaymentTimelineCard old) {
    super.didUpdateWidget(old);
    if (old.booking.paymentStatus != widget.booking.paymentStatus) _lines = _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    if (b.status == BookingStatus.cancelled) return const SizedBox.shrink();
    return FutureBuilder<(LedgerEntry?, LedgerEntry?)>(
      future: _lines,
      builder: (context, snap) {
        final lines = snap.data ?? (null, null);
        final t = PaymentTimeline.of(b, earning: lines.$1, commission: lines.$2);
        final firstOpen = t.steps.indexWhere((s) => !s.done);
        return AppCard(
          key: const ValueKey('paymentTimeline'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'ptTitle'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
            const SizedBox(height: 10),
            for (var i = 0; i < t.steps.length; i++) _stepRow(context, t.steps[i], current: i == firstOpen),
            if (t.commissionPaise != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(trf(context, 'ptCommission', {'amount': formatPaise(t.commissionPaise!)}), key: const ValueKey('ptCommission'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Text(tr(context, 'ptNext_${t.next.name}'), key: const ValueKey('ptNext'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        );
      },
    );
  }

  Widget _stepRow(BuildContext context, PaymentStepInfo s, {required bool current}) {
    final color = s.done ? AppColors.success : (current ? AppColors.warning : AppColors.faint);
    final parts = [
      if (s.paise != null) formatPaise(s.paise!),
      if (s.at != null) formatDateTime(s.at!),
    ];
    return Padding(
      key: ValueKey('ptStep_${s.step.name}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(s.done ? Icons.check_circle_rounded : (current ? Icons.timelapse_rounded : Icons.radio_button_unchecked), color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'ptStep_${s.step.name}'), style: TextStyle(fontWeight: current ? FontWeight.w800 : FontWeight.w600)),
            if (parts.isNotEmpty) Text(parts.join(' · '), style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}
