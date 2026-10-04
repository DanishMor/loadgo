import 'package:flutter/material.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import 'lr_screen.dart';
import 'pod_screen.dart';

/// "View LR" and (once picked up) "View POD" for a booking, either role.
class TripDocumentButtons extends StatelessWidget {
  final Booking booking;
  const TripDocumentButtons({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    if (booking.status == BookingStatus.cancelled) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('viewLr'),
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => LrScreen(bookingId: booking.id))),
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(tr(context, 'viewLr')),
        ),
        if (booking.pickupOtpVerified)
          OutlinedButton.icon(
            key: const ValueKey('viewPod'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PodScreen(booking: booking))),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(tr(context, 'viewPod')),
          ),
      ],
    );
  }
}
