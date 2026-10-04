import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/services/booking_service.dart';
import '../core/services/pricing_service.dart';
import '../core/widgets/common.dart';

/// Cancel an advance booking before the driver starts it. The dialog says
/// whether it is free or what the recorded charge is (from config/pricing).
class CancelScheduledButton extends StatefulWidget {
  final Booking booking;

  /// Injectable clock for tests.
  final DateTime Function() now;

  const CancelScheduledButton({super.key, required this.booking, this.now = DateTime.now});

  @override
  State<CancelScheduledButton> createState() => _CancelScheduledButtonState();
}

class _CancelScheduledButtonState extends State<CancelScheduledButton> {
  bool _busy = false;

  int get _charge => PricingService.config.cancellation.chargeForScheduled(
        now: widget.now(),
        scheduledAt: widget.booking.scheduledAt!,
        farePaise: widget.booking.agreedFarePaise ?? widget.booking.fareEstimate,
      );

  Future<void> _cancel() async {
    final hours = PricingService.config.cancellation.scheduledFreeHours;
    final charge = _charge;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'cancelBooking')),
        content: Text(
          charge == 0 ? trf(c, 'cancelScheduledFree', {'h': hours}) : trf(c, 'cancelScheduledCharge', {'amount': formatPaise(charge), 'h': hours}),
          key: const ValueKey('cancelScheduledNote'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'keepBooking'))),
          FilledButton(
            key: const ValueKey('cancelScheduledConfirm'),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr(c, 'cancelBooking')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final done = tr(context, 'bookingCancelledByYou');
    final failed = tr(context, 'somethingWrong');
    try {
      await BookingService.cancelScheduledByCustomer(widget.booking.id, now: widget.now());
      messenger.showSnackBar(SnackBar(content: Text(done), behavior: SnackBarBehavior.floating));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed), behavior: SnackBarBehavior.floating));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        key: const ValueKey('cancelScheduled'),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
        onPressed: _busy ? null : _cancel,
        icon: const Icon(Icons.event_busy_rounded),
        label: Text(tr(context, 'cancelBooking')),
      ),
    );
  }
}
