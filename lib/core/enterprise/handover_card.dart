import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/handover.dart';
import '../services/handover_service.dart';
import '../widgets/common.dart';

/// Container handover on a two-leg shipment (IE10), shown to the driver of
/// either leg. Nothing for an ordinary booking.
class HandoverCard extends StatefulWidget {
  final Booking booking;
  const HandoverCard({super.key, required this.booking});

  @override
  State<HandoverCard> createState() => _HandoverCardState();
}

class _HandoverCardState extends State<HandoverCard> {
  late final Future<LegRef?> _ref = HandoverService.legOf(widget.booking);
  final _seal = TextEditingController();
  final _container = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _seal.dispose();
    _container.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on HandoverException catch (e) {
      if (mounted) showSnack(context, tr(context, e.reason == 'seal' || e.reason == 'container' ? 'hoInvalid' : 'somethingWrong'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, TextEditingController c, String label, {int max = 20}) =>
      TextField(key: ValueKey(key), controller: c, maxLength: max, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: label, counterText: ''));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LegRef?>(
      future: _ref,
      builder: (context, ref) {
        final leg = ref.data;
        if (leg == null) return const SizedBox.shrink();
        return StreamBuilder<Handover?>(
          stream: HandoverService.watch(leg.shipmentId),
          builder: (context, snap) {
            final h = snap.data;
            final b = widget.booking;
            final children = <Widget>[];
            if (h?.leg1 != null) {
              children.add(Text(trf(context, 'hoDetails', {'container': h!.containerNumber.isEmpty ? '-' : h.containerNumber, 'seal': h.leg1!.sealNumber.isEmpty ? '-' : h.leg1!.sealNumber}), key: const ValueKey('hoDetails')));
            }
            if (h?.complete == true) {
              children.add(Text(tr(context, h!.sealMatches ? 'hoDone' : 'hoSealDiffers'), key: ValueKey(h.sealMatches ? 'hoDone' : 'hoSealDiffers'), style: TextStyle(fontWeight: FontWeight.w700, color: h.sealMatches ? AppColors.success : AppColors.warning)));
            } else if (leg.leg == 1) {
              if (h?.leg1 != null) {
                children.add(Text(tr(context, 'hoLeg1Done'), key: const ValueKey('hoLeg1Done'), style: TextStyle(color: AppColors.muted)));
              } else if (b.status == BookingStatus.unloading || b.status == BookingStatus.delivered) {
                children.addAll([
                  _field('hoContainer', _container, tr(context, 'containerNumber'), max: 15),
                  _field('hoSeal', _seal, tr(context, 'hoSeal')),
                  const SizedBox(height: 8),
                  FilledButton(key: const ValueKey('hoHandOver'), onPressed: _busy ? null : () => _run(() => HandoverService.handOver(b, leg, container: _container.text, seal: _seal.text)), child: Text(tr(context, 'hoHandOver'))),
                ]);
              }
            } else {
              if (h?.leg1 == null) {
                children.add(Text(tr(context, 'hoWaiting'), key: const ValueKey('hoWaiting'), style: TextStyle(color: AppColors.muted)));
              } else {
                children.addAll([
                  _field('hoSeal', _seal, tr(context, 'hoSeal')),
                  const SizedBox(height: 8),
                  FilledButton(key: const ValueKey('hoReceive'), onPressed: _busy ? null : () => _run(() => HandoverService.receive(b, leg, seal: _seal.text)), child: Text(tr(context, 'hoReceive'))),
                ]);
              }
            }
            if (children.isEmpty) return const SizedBox.shrink();
            return AppCard(
              key: const ValueKey('handoverCard'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'hoTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                ...children,
              ]),
            );
          },
        );
      },
    );
  }
}
