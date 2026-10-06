import 'package:flutter/material.dart';

import '../core/fleet/fleet_logic.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/fleet.dart';
import '../core/models/vehicle.dart';
import '../core/models/vehicle_expense.dart';
import '../core/services/expense_service.dart';
import '../core/services/fleet_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Utilisation, idle days, revenue, expenses, maintenance due and who the fleet
/// works for, over the last 30 days (N13, BIZ12). Money is a record.
class FleetAnalyticsScreen extends StatefulWidget {
  final Stream<List<Vehicle>>? vehicles;
  final Stream<List<Booking>>? bookings;
  final Stream<List<FleetMember>>? members;
  final Stream<List<VehicleExpense>>? expenses;
  final DateTime Function() now;

  const FleetAnalyticsScreen({super.key, this.vehicles, this.bookings, this.members, this.expenses, this.now = DateTime.now});

  @override
  State<FleetAnalyticsScreen> createState() => _FleetAnalyticsScreenState();
}

class _FleetAnalyticsScreenState extends State<FleetAnalyticsScreen> {
  late final Stream<List<Vehicle>> _vehicles = (widget.vehicles ?? VehicleService.watchMine()).asBroadcastStream();
  late final Stream<List<Booking>> _bookings = (widget.bookings ?? FleetService.watchFleetBookings()).asBroadcastStream();
  late final Stream<List<FleetMember>> _members = (widget.members ?? FleetService.watchMembers()).asBroadcastStream();
  late final Stream<List<VehicleExpense>> _expenses = (widget.expenses ?? ExpenseService.watchMine()).asBroadcastStream();

  Widget _stat(String label, String value, Key key) => Expanded(
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, key: key, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.title)),
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
          builder: (context, members) => LiveStream<List<VehicleExpense>>(
            stream: () => _expenses,
            compact: true,
            builder: (context, expenses) {
              if (vehicles.isEmpty) return EmptyState(icon: Icons.insights_outlined, title: tr(context, 'fleetNoVehicles'));
              final a = FleetAnalytics.from(vehicles: vehicles, bookings: bookings, expenses: expenses, members: members, now: widget.now());
              return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                Row(children: [
                  _stat(tr(context, 'faRevenue'), formatPaise(a.revenuePaise), const ValueKey('faRevenue')),
                  const SizedBox(width: 8),
                  _stat(tr(context, 'faExpenses'), formatPaise(a.expensesPaise), const ValueKey('faExpenses')),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _stat(tr(context, 'faNet'), formatPaise(a.netPaise), const ValueKey('faNet')),
                  const SizedBox(width: 8),
                  _stat(tr(context, 'faMaintenance'), '${a.maintenanceDue}', const ValueKey('faMaintenance')),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _stat(tr(context, 'faCustomers'), '${a.customersServed}', const ValueKey('faCustomers')),
                  const SizedBox(width: 8),
                  _stat(tr(context, 'faRepeat'), '${a.repeatCustomers}', const ValueKey('faRepeat')),
                ]),
                const SizedBox(height: 14),
                Text(tr(context, 'faUtilisation'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                for (final r in a.vehicles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      key: ValueKey('faVehicle_${r.vehicle.id}'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(r.vehicle.number, style: const TextStyle(fontWeight: FontWeight.w800))),
                          Text('${r.daysOnRoad} / ${FleetAnalytics.window}', key: ValueKey('faDays_${r.vehicle.id}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(value: r.utilisation, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                        const SizedBox(height: 4),
                        Text('${tr(context, 'faIdleDays')}: ${r.idleDays} · ${tr(context, 'faNet')}: ${formatPaise(r.netPaise)}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      ]),
                    ),
                  ),
                if (a.topCustomers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(tr(context, 'faTopCustomers'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  for (final c in a.topCustomers) ListTile(dense: true, contentPadding: EdgeInsets.zero, key: ValueKey('faTop_${c.customerId}'), title: Text(c.customerId), trailing: Text(trf(context, 'faTrips', {'n': c.trips}))),
                ],
                if (a.tripsPerDriver.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(tr(context, 'faDriverTrips'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  for (final e in a.tripsPerDriver.entries)
                    ListTile(dense: true, contentPadding: EdgeInsets.zero, key: ValueKey('faDriver_${e.key}'), title: Text((a.driverNames[e.key] ?? '').isEmpty ? e.key : a.driverNames[e.key]!), trailing: Text(trf(context, 'faTrips', {'n': e.value}))),
                ],
              ]);
            },
          ),
        ),
      ),
    );
  }
}
