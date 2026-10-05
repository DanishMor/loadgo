import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/driver_extras.dart';
import '../services/driver_extras_service.dart';
import 'common.dart';

/// After delivery the customer can record a tip for the driver (once).
/// Record only: the customer hands it over directly.
class TipCard extends StatefulWidget {
  final Booking booking;
  const TipCard({super.key, required this.booking});

  @override
  State<TipCard> createState() => _TipCardState();
}

class _TipCardState extends State<TipCard> {
  final _ctrl = TextEditingController();
  late final Stream<Tip?> _tip = DriverExtrasService.watchTipFor(widget.booking.id).asBroadcastStream();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send(int paise) async {
    setState(() => _busy = true);
    try {
      await DriverExtrasService.addTip(widget.booking, paise);
      if (mounted) showSnack(context, tr(context, 'tipSent'));
    } on TipException catch (e) {
      if (mounted) showSnack(context, tr(context, e.reason == 'amount' ? 'tipInvalid' : 'tipAlready'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _custom() {
    final rupees = int.tryParse(_ctrl.text.trim());
    if (rupees == null || rupees < 1 || rupees > Tip.maxPaise ~/ 100) return showSnack(context, tr(context, 'tipInvalid'));
    _send(rupees * 100);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tip?>(
      stream: _tip,
      builder: (context, snap) {
        final tip = snap.data;
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr(context, 'tipTitle'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (tip != null)
                Text(trf(context, 'tipGiven', {'amount': formatPaise(tip.amountPaise)}),
                    key: const ValueKey('tipGiven'), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700))
              else ...[
                Wrap(spacing: 8, children: [
                  for (final p in Tip.quickAmounts)
                    ActionChip(
                      key: ValueKey('tip_$p'),
                      label: Text(formatPaise(p)),
                      onPressed: _busy ? null : () => _send(p),
                    ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('tipCustom'),
                      controller: _ctrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [LengthLimitingTextInputFormatter(10), FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(prefixIcon: const Icon(Icons.currency_rupee_rounded), labelText: tr(context, 'tipOther')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(key: const ValueKey('tipSend'), onPressed: _busy ? null : _custom, child: Text(tr(context, 'tipSendButton'))),
                ]),
                const SizedBox(height: 4),
                Text(tr(context, 'tipNote'), style: const TextStyle(color: AppColors.faint, fontSize: 12)),
              ],
            ],
          ),
        );
      },
    );
  }
}
