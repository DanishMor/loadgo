import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/fleet.dart';
import '../core/models/vehicle.dart';
import '../core/services/fleet_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';

/// Vehicles, drivers, trips in progress, idle vehicles and earnings per
/// vehicle. Earnings are a record from delivered bookings, not a payout.
class FleetDashboard extends StatefulWidget {
  /// Injectable for tests.
  final Stream<List<Vehicle>>? vehicles;
  final Stream<List<Booking>>? bookings;
  final Stream<List<FleetMember>>? members;
  final DateTime Function() now;

  const FleetDashboard({super.key, this.vehicles, this.bookings, this.members, this.now = DateTime.now});

  @override
  State<FleetDashboard> createState() => _FleetDashboardState();
}

class _FleetDashboardState extends State<FleetDashboard> {
  late final Stream<List<Vehicle>> _vehicles = (widget.vehicles ?? VehicleService.watchMine()).asBroadcastStream();
  late final Stream<List<Booking>> _bookings = (widget.bookings ?? FleetService.watchFleetBookings()).asBroadcastStream();
  late final Stream<List<FleetMember>> _members = (widget.members ?? FleetService.watchMembers()).asBroadcastStream();

  Widget _stat(String label, String value, {Key? key}) => Expanded(
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, key: key, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.title)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LiveStream<List<Vehicle>>(
      stream: () => _vehicles,
      builder: (context, vehicles) => LiveStream<List<Booking>>(
        stream: () => _bookings,
        compact: true,
        builder: (context, bookings) => LiveStream<List<FleetMember>>(
          stream: () => _members,
          compact: true,
          builder: (context, members) {
            final s = FleetSummary.from(vehicles: vehicles, bookings: bookings, members: members, now: widget.now());
            if (vehicles.isEmpty) {
              return EmptyState(icon: Icons.local_shipping_outlined, title: tr(context, 'fleetNoVehicles'), subtitle: tr(context, 'fleetNoVehiclesSub'));
            }
            return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Row(children: [
                _stat(tr(context, 'fleetVehicles'), '${vehicles.length}', key: const ValueKey('statVehicles')),
                const SizedBox(width: 8),
                _stat(tr(context, 'fleetActiveTrips'), '${s.activeTrips}', key: const ValueKey('statActive')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _stat(tr(context, 'fleetIdle'), '${s.idleVehicles}', key: const ValueKey('statIdle')),
                const SizedBox(width: 8),
                _stat(tr(context, 'fleetDriversCount'), '${s.activeDrivers}', key: const ValueKey('statDrivers')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _stat(tr(context, 'todayEarnings'), formatPaise(s.todayEarningsPaise), key: const ValueKey('statToday')),
                const SizedBox(width: 8),
                _stat(tr(context, 'totalEarnings'), formatPaise(s.totalEarningsPaise), key: const ValueKey('statTotal')),
              ]),
              const SizedBox(height: 6),
              Text(tr(context, 'fleetEarningsNote'), style: const TextStyle(color: AppColors.faint, fontSize: 12)),
              const SizedBox(height: 14),
              Text(tr(context, 'fleetPerVehicle'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final r in s.vehicles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    key: ValueKey('fleetRow_${r.vehicle.id}'),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.vehicle.number, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text('${vehicleTypeLabel(context, r.vehicle.type)} • ${r.driverName ?? tr(context, 'fleetNoDriver')}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, children: [
                            StatusChip(label: availabilityLabel(context, r.vehicle.availability), color: availabilityColor(r.vehicle.availability)),
                            if (r.activeTrips > 0) StatusChip(label: trf(context, 'fleetTripsActive', {'n': r.activeTrips}), color: AppColors.primary),
                            if (r.idle) StatusChip(label: tr(context, 'fleetIdleChip'), color: AppColors.warning),
                          ]),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(formatPaise(r.earningsPaise), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                        Text(trf(context, 'fleetTripsDone', {'n': r.deliveredTrips}), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ]),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
