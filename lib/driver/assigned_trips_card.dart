import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/services/transporter_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/logistics_labels.dart';

/// Driver home: trips a transporter assigned to this driver (the booking is
/// the company's; the driver moves it through the trip steps). Shows nothing
/// when there are none.
class AssignedTripsCard extends StatefulWidget {
  final Stream<List<Booking>>? bookings;
  final void Function(String bookingId) onOpen;

  const AssignedTripsCard({super.key, this.bookings, required this.onOpen});

  @override
  State<AssignedTripsCard> createState() => _AssignedTripsCardState();
}

class _AssignedTripsCardState extends State<AssignedTripsCard> {
  late final Stream<List<Booking>> _bookings = (widget.bookings ?? TransporterService.watchAssignedToMe()).asBroadcastStream();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Booking>>(
      stream: _bookings,
      builder: (context, snap) {
        final trips = [for (final b in snap.data ?? const <Booking>[]) if (b.isActive) b];
        if (trips.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            key: const ValueKey('assignedTrips'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'trpMyAssigned'), style: const TextStyle(fontWeight: FontWeight.w800)),
              for (final b in trips)
                InkWell(
                  key: ValueKey('assignedTrip_${b.id}'),
                  onTap: () => widget.onOpen(b.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Expanded(child: Text('${b.pickup} → ${b.drop}\n${b.assignedVehicleNumber}', style: const TextStyle(fontWeight: FontWeight.w600))),
                      StatusChip(label: bookingStatusLabel(context, b.status), color: bookingStatusColor(b.status)),
                    ]),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}
