import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/services/repeat_service.dart';
import '../core/widgets/common.dart';

/// On a booking: add the driver to favourites or block them.
class DriverTrustRow extends StatelessWidget {
  final Booking booking;

  const DriverTrustRow({super.key, required this.booking});

  Future<void> _favourite(BuildContext context) async {
    await RepeatService.addFavourite(driverId: booking.driverId, name: booking.driverName, vehicleNumber: booking.vehicleNumber);
    if (context.mounted) showSnack(context, tr(context, 'driverFavourited'));
  }

  Future<void> _block(BuildContext context) async {
    try {
      await RepeatService.blockDriver(driverId: booking.driverId, name: booking.driverName);
      if (context.mounted) showSnack(context, tr(context, 'driverBlocked'));
    } on BlockLimitException {
      if (context.mounted) showSnack(context, tr(context, 'blockLimit'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, children: [
      OutlinedButton.icon(
        key: const ValueKey('addFavourite'),
        onPressed: () => _favourite(context),
        icon: const Icon(Icons.favorite_border_rounded, size: 18),
        label: Text(tr(context, 'addFavourite')),
      ),
      TextButton.icon(
        key: const ValueKey('blockDriver'),
        onPressed: () => _block(context),
        icon: const Icon(Icons.block_rounded, size: 18),
        label: Text(tr(context, 'blockDriver')),
      ),
    ]);
  }
}
