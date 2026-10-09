import 'package:flutter/material.dart';

import '../core/fleet/transporter_board.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/fleet.dart';
import '../core/models/vehicle.dart';
import '../core/transporter/transporter_logic.dart';
import '../core/widgets/common.dart';
import '../core/widgets/logistics_labels.dart';

/// Trips by status, vehicle use, trips per driver and party-wise pending
/// money on the transporter dashboard (MASTER-6 Task 28).
class TransporterBoardCard extends StatelessWidget {
  final List<Vehicle> vehicles;
  final List<Booking> bookings;
  final List<FleetMember> members;
  final List<TripAccount> accounts;
  final DateTime now;
  const TransporterBoardCard({super.key, required this.vehicles, required this.bookings, required this.members, required this.accounts, required this.now});

  Widget _title(BuildContext c, String key) => Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(tr(c, key), style: const TextStyle(fontWeight: FontWeight.w800)));

  @override
  Widget build(BuildContext context) {
    final b = TransporterBoard.compute(vehicles: vehicles, bookings: bookings, members: members, accounts: accounts, now: now);
    final shown = [for (final s in TransporterBoard.statusOrder) if ((b.tripsByStatus[s] ?? 0) > 0) s];
    return AppCard(
      key: const ValueKey('transporterBoard'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'tbTitle'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        _title(context, 'tbStatus'),
        if (shown.isEmpty) Text(tr(context, 'tbNoTrips'), key: const ValueKey('tbNoTrips'), style: TextStyle(color: AppColors.muted)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in shown) Chip(key: ValueKey('tbStatus_$s'), label: Text('${bookingStatusLabel(context, s)}: ${b.tripsByStatus[s]}')),
        ]),
        _title(context, 'tbUse'),
        Text(trf(context, 'tbUtilisation', {'p': (b.utilisation * 100).round()}), key: const ValueKey('tbUtilisation')),
        for (final v in b.leastUsed) Text('${v.vehicle.number}: ${trf(context, 'tbDaysOnRoad', {'d': v.daysOnRoad, 'w': 30})}', key: ValueKey('tbIdle_${v.vehicle.id}'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        if (b.drivers.isNotEmpty) ...[
          _title(context, 'tbDrivers'),
          for (final d in b.drivers) Text('${d.driver}: ${trf(context, 'fleetTripsDone', {'n': d.trips})}', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
        _title(context, 'tbParties'),
        if (b.parties.isEmpty) Text(tr(context, 'tbNoDue'), key: const ValueKey('tbNoDue'), style: TextStyle(color: AppColors.muted)),
        for (final p in b.parties)
          Row(key: ValueKey('tbParty_${p.partyId}'), children: [
            Expanded(child: Text(p.partyName.isEmpty ? p.partyId : p.partyName, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(formatPaise(p.duePaise), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.warning)),
          ]),
        if (b.parties.isNotEmpty) Text(trf(context, 'tbTotalDue', {'amount': formatPaise(b.totalDuePaise)}), key: const ValueKey('tbTotalDue'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
