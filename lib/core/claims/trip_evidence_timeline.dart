import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../constants/logistics.dart';
import '../models/booking.dart';
import '../services/booking_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import '../widgets/logistics_labels.dart';

/// One line of what the trip's own records say happened (MASTER-5 Task 34).
class EvidenceStep {
  /// `status`, `pickupProof`, `deliveryProof`, `damage` or `cancelled`.
  final String kind;
  final DateTime? at;
  final Map<String, Object> args;
  const EvidenceStep(this.kind, this.at, [this.args = const {}]);
}

/// The facts that matter in a dispute, in time order, taken from the booking
/// itself: each status with its time, what the driver recorded at pickup and
/// delivery, any damage note, and a cancellation. Nothing is invented; a step
/// without a recorded time keeps its place by the flow order.
class TripEvidence {
  TripEvidence._();

  static List<EvidenceStep> of(Booking b) {
    final steps = <EvidenceStep>[];
    final order = [...BookingStatus.flow, BookingStatus.cancelled];
    final statuses = b.timeline.keys.toList()..sort((a, c) {
      final t = b.timeline[a]!.compareTo(b.timeline[c]!);
      return t != 0 ? t : order.indexOf(a).compareTo(order.indexOf(c));
    });
    for (final s in statuses) {
      steps.add(EvidenceStep('status', b.timeline[s], {'status': s}));
      if (s == BookingStatus.pickedUp && b.pickupProof != null) {
        final p = b.pickupProof!;
        steps.add(EvidenceStep('pickupProof', b.timeline[s], {'n': p.packages, 't': p.weightTons, 'seal': p.sealNumber}));
        if (p.damageNote.isNotEmpty) steps.add(EvidenceStep('damage', b.timeline[s], {'where': 'pickup', 'note': p.damageNote}));
      }
      if (s == BookingStatus.delivered && b.deliveryProof != null) {
        final d = b.deliveryProof!;
        steps.add(EvidenceStep('deliveryProof', b.timeline[s], {'name': d.receiverName}));
        if (d.damageNote.isNotEmpty) steps.add(EvidenceStep('damage', b.timeline[s], {'where': 'delivery', 'note': d.damageNote}));
      }
    }
    if (b.cancellation != null) {
      steps.add(EvidenceStep('cancelled', b.timeline[BookingStatus.cancelled], {'by': b.cancellation!.by, 'charge': b.cancellation!.chargePaise}));
    }
    return steps;
  }
}

/// The evidence of a booking as a list under a dispute.
class TripEvidenceTimeline extends StatelessWidget {
  final String bookingId;
  const TripEvidenceTimeline({super.key, required this.bookingId});

  String _line(BuildContext context, EvidenceStep s) => switch (s.kind) {
        'status' => bookingStatusLabel(context, s.args['status']! as String),
        'pickupProof' => trf(context, 'evPickupProof', {'n': s.args['n']!, 't': s.args['t']!, 'seal': (s.args['seal']! as String).isEmpty ? '-' : s.args['seal']!}),
        'deliveryProof' => trf(context, 'evDeliveryProof', {'name': (s.args['name']! as String).isEmpty ? '-' : s.args['name']!}),
        'damage' => trf(context, s.args['where'] == 'pickup' ? 'evDamagePickup' : 'evDamageDelivery', {'note': s.args['note']!}),
        _ => trf(context, 'evCancelled', {'by': tr(context, 'dspRole_${s.args['by']}'), 'amount': formatPaise((s.args['charge']! as int))}),
      };

  @override
  Widget build(BuildContext context) {
    return LiveStream<Booking?>(
      stream: () => BookingService.watch(bookingId),
      compact: true,
      builder: (context, b) {
        final steps = b == null ? const <EvidenceStep>[] : TripEvidence.of(b);
        if (steps.isEmpty) return Text(tr(context, 'evNone'), style: TextStyle(color: AppColors.muted));
        return Column(children: [
          for (final (i, s) in steps.indexed)
            ListTile(
              key: ValueKey('evidence_$i'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(s.kind == 'status' ? Icons.circle : (s.kind == 'cancelled' || s.kind == 'damage' ? Icons.warning_amber_rounded : Icons.fact_check_outlined), size: s.kind == 'status' ? 10 : 20, color: s.kind == 'damage' || s.kind == 'cancelled' ? AppColors.warning : AppColors.primary),
              title: Text(_line(context, s)),
              subtitle: s.at == null ? null : Text(formatDateTime(s.at!)),
            ),
        ]);
      },
    );
  }
}
