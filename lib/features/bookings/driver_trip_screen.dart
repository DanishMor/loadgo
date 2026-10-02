import 'package:flutter/material.dart';

import '../../core/constants/logistics.dart';
import '../../core/models/booking.dart';
import '../../core/services/booking_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import 'booking_widgets.dart';

void openDriverTrip(BuildContext context, String bookingId) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => DriverTripScreen(bookingId: bookingId)));
}

/// Driver's active trip: details, timeline and the button for the next status.
class DriverTripScreen extends StatelessWidget {
  final String bookingId;

  const DriverTripScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return BookingDetailScaffold(
      bookingId: bookingId,
      title: tr(context, 'tripDetails'),
      builder: (context, booking) => ListView(
        // Extra bottom space keeps the action button clear of floating snackbars.
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
        children: [
          BookingSummary(booking: booking),
          const SizedBox(height: 14),
          BookingTimeline(booking: booking),
          const SizedBox(height: 20),
          _NextStatusButton(booking: booking),
        ],
      ),
    );
  }
}

class _NextStatusButton extends StatefulWidget {
  final Booking booking;
  const _NextStatusButton({required this.booking});

  @override
  State<_NextStatusButton> createState() => _NextStatusButtonState();
}

class _NextStatusButtonState extends State<_NextStatusButton> {
  bool _busy = false;

  static String _labelKey(String next) => switch (next) {
        BookingStatus.pickedUp => 'markPickedUp',
        BookingStatus.inTransit => 'markInTransit',
        _ => 'markDelivered',
      };

  Future<bool> _confirmDelivered() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'markDelivered')),
        content: RouteText(pickup: widget.booking.pickup, drop: widget.booking.drop, fontSize: 15),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr(dialogContext, 'cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(tr(dialogContext, 'markDelivered'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _advance(String next) async {
    // Delivery closes the load and can't be undone, so ask first.
    if (next == BookingStatus.delivered && !await _confirmDelivered()) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await BookingService.advance(widget.booking.id);
      if (mounted) showSnack(context, tr(context, 'statusUpdated'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.booking.nextStatus;
    if (next == null) {
      return Center(
        child: StatusChip(label: tr(context, 'tripCompleted'), color: AppColors.success),
      );
    }
    return PrimaryButton(
      label: tr(context, _labelKey(next)),
      icon: next == BookingStatus.delivered ? Icons.flag_rounded : Icons.arrow_forward_rounded,
      loading: _busy,
      onPressed: () => _advance(next),
    );
  }
}
