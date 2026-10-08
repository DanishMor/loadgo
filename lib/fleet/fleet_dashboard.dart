import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/fleet/fleet_logic.dart';
import '../core/models/fleet.dart';
import '../core/models/load.dart';
import '../core/services/load_service.dart';
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
  final Stream<List<Load>>? openLoads;
  final DateTime Function() now;

  /// Shown at the top of the scrolling page (the transporter shortcuts), also when there are no vehicles yet.
  final Widget? header;

  const FleetDashboard({super.key, this.vehicles, this.bookings, this.members, this.openLoads, this.now = DateTime.now, this.header});

  @override
  State<FleetDashboard> createState() => _FleetDashboardState();
}

class _FleetDashboardState extends State<FleetDashboard> {
  late final Stream<List<Vehicle>> _vehicles = (widget.vehicles ?? VehicleService.watchMine()).asBroadcastStream();
  late final Stream<List<Booking>> _bookings = (widget.bookings ?? FleetService.watchFleetBookings()).asBroadcastStream();
  late final Stream<List<Load>> _loads = (widget.openLoads ?? LoadService.watchOpen()).asBroadcastStream();
  late final Stream<List<FleetMember>> _members = (widget.members ?? FleetService.watchMembers()).asBroadcastStream();

  Widget _stat(String label, String value, {Key? key}) => Expanded(
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, key: key, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.title)),
          ]),
        ),
      );

  /// SM12: trips with a breakdown that asked for a replacement, and the idle
  /// vehicles of this fleet that could take over.
  Widget _breakdowns(BuildContext context, List<Vehicle> vehicles, List<Booking> bookings) {
    final broken = [for (final b in bookings) if (b.isActive && b.breakdown?.replacementRequested == true) b];
    if (broken.isEmpty) return const SizedBox.shrink();
    final now = widget.now();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: AppCard(
        key: const ValueKey('fleetBreakdowns'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.car_crash_outlined, color: AppColors.warning),
            const SizedBox(width: 8),
            Text(tr(context, 'fleetBreakdownTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          for (final b in broken)
            Builder(builder: (context) {
              final options = replacementCandidates(vehicles, weight: b.weight, preferType: b.vehicleType, excludeId: b.vehicleId, now: now);
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  options.isEmpty
                      ? trf(context, 'fleetBreakdownNone', {'vehicle': b.vehicleNumber})
                      : trf(context, 'fleetBreakdownLine', {'vehicle': b.vehicleNumber, 'list': options.map((v) => v.number).join(', ')}),
                  key: ValueKey('breakdownLine_${b.id}'),
                ),
              );
            }),
        ]),
      ),
    );
  }

  /// SM9: open loads that fit an idle vehicle which has a driver.
  Widget _suggestions(BuildContext context, List<Vehicle> vehicles) {
    return StreamBuilder<List<Load>>(
      stream: _loads,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(error: snap.error);
        final idle = [for (final v in vehicles) if (v.canTakeBooking) v];
        final list = suggestAllocation(snap.data ?? const [], idle, now: widget.now());
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: AppCard(
            key: const ValueKey('fleetSuggestions'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'fleetSuggestTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              for (final s in list.take(5))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(trf(context, 'fleetSuggestLine', {'load': '${s.load.pickup} → ${s.load.drop} (${formatNum(s.load.weight)} T)', 'vehicle': s.vehicle.number}), key: ValueKey('suggest_${s.load.id}')),
                ),
              const SizedBox(height: 6),
              Text(tr(context, 'fleetSuggestNote'), style: TextStyle(fontSize: 12, color: AppColors.faint)),
            ]),
          ),
        );
      },
    );
  }

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
              final empty = EmptyState(icon: Icons.local_shipping_outlined, title: tr(context, 'fleetNoVehicles'), subtitle: tr(context, 'fleetNoVehiclesSub'));
              if (widget.header == null) return empty;
              // With the shortcuts on top the page scrolls, so the message is plain text, not a centred block.
              return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                widget.header!,
                const SizedBox(height: 24),
                Icon(Icons.local_shipping_outlined, size: 56, color: AppColors.muted),
                const SizedBox(height: 12),
                Text(tr(context, 'fleetNoVehicles'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(tr(context, 'fleetNoVehiclesSub'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              ]);
            }
            return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              if (widget.header != null) widget.header!,
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
              Text(tr(context, 'fleetEarningsNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
              _breakdowns(context, vehicles, bookings),
              _suggestions(context, vehicles),
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
                          Text('${vehicleTypeLabel(context, r.vehicle.type)} • ${r.driverName ?? tr(context, 'fleetNoDriver')}', style: TextStyle(color: AppColors.muted, fontSize: 13)),
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
                        Text(trf(context, 'fleetTripsDone', {'n': r.deliveredTrips}), style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
