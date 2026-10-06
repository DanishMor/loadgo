import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/earnings.dart';
import '../models/fleet.dart';
import '../models/load.dart';
import '../models/vehicle.dart';
import '../models/vehicle_expense.dart';

/// Vehicles that could carry [weight] tonnes of a load now, best fit first:
/// same type as [preferType], then the smallest sufficient capacity (V11,
/// SM12). Inactive, busy, expired-paper and [excludeId] vehicles are skipped.
List<Vehicle> replacementCandidates(Iterable<Vehicle> vehicles, {required num weight, String? preferType, String? excludeId, DateTime? now}) {
  final t = now ?? DateTime.now();
  final list = [
    for (final v in vehicles)
      if (v.id != excludeId && v.canTakeBooking && v.capacity >= weight && !v.papersBlocked(t)) v,
  ];
  list.sort((a, b) {
    final ta = a.type == preferType ? 0 : 1, tb = b.type == preferType ? 0 : 1;
    if (ta != tb) return ta.compareTo(tb);
    return a.capacity.compareTo(b.capacity);
  });
  return list;
}

/// One suggested pairing of an open load and an idle fleet vehicle.
class AllocationSuggestion {
  final Load load;
  final Vehicle vehicle;
  final String? driverId;

  const AllocationSuggestion(this.load, this.vehicle, this.driverId);
}

/// SM9: for each open load (newest first) the best idle vehicle that fits its
/// type and weight; every vehicle is suggested once. Vehicles without an
/// assigned driver are skipped (nobody could accept for them). The owner
/// tells the driver; nothing is booked by this.
List<AllocationSuggestion> suggestAllocation(Iterable<Load> openLoads, Iterable<Vehicle> idleVehicles, {DateTime? now}) {
  final pool = [for (final v in idleVehicles) if (v.assignedDriverId != null) v];
  final out = <AllocationSuggestion>[];
  for (final l in openLoads) {
    if (!l.isOpen || pool.isEmpty) continue;
    final fits = replacementCandidates(pool, weight: l.weight, preferType: l.vehicleType, now: now).where((v) => v.type == l.vehicleType).toList();
    if (fits.isEmpty) continue;
    final v = fits.first;
    out.add(AllocationSuggestion(l, v, v.assignedDriverId));
    pool.remove(v);
  }
  return out;
}

/// Per-vehicle figures for the last 30 days.
class FleetVehicleStats {
  final Vehicle vehicle;
  final int daysOnRoad;
  final int revenuePaise;
  final int expensesPaise;

  const FleetVehicleStats({required this.vehicle, required this.daysOnRoad, required this.revenuePaise, required this.expensesPaise});

  int get idleDays => FleetAnalytics.window - daysOnRoad;
  double get utilisation => daysOnRoad / FleetAnalytics.window;
  int get netPaise => revenuePaise - expensesPaise;
}

class CustomerTrips {
  final String customerId;
  final int trips;

  const CustomerTrips(this.customerId, this.trips);
}

/// Fleet analytics (N13) and the transporter view (BIZ12) over the last 30
/// days: utilisation, idle days, revenue, expenses, maintenance due, who the
/// fleet works for and what each driver did. Money is a record from delivered
/// bookings and the owner's expense lines, not a payout.
class FleetAnalytics {
  static const window = 30;

  final List<FleetVehicleStats> vehicles;
  final int revenuePaise;
  final int expensesPaise;
  final int maintenanceDue;
  final int customersServed;
  final int repeatCustomers;
  final List<CustomerTrips> topCustomers;
  final Map<String, int> tripsPerDriver; // driverId -> delivered trips (30 days)
  final Map<String, String> driverNames;

  const FleetAnalytics({
    required this.vehicles,
    required this.revenuePaise,
    required this.expensesPaise,
    required this.maintenanceDue,
    required this.customersServed,
    required this.repeatCustomers,
    required this.topCustomers,
    required this.tripsPerDriver,
    required this.driverNames,
  });

  int get netPaise => revenuePaise - expensesPaise;

  /// Average utilisation of all vehicles, 0..1.
  double get utilisation => vehicles.isEmpty ? 0 : vehicles.fold<double>(0, (a, v) => a + v.utilisation) / vehicles.length;

  factory FleetAnalytics.from({
    required Iterable<Vehicle> vehicles,
    required Iterable<Booking> bookings,
    required Iterable<VehicleExpense> expenses,
    Iterable<FleetMember> members = const [],
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: window - 1));
    final names = {for (final m in members) m.driverId: m.driverName};

    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final recent = [
      for (final b in bookings)
        if (b.status != BookingStatus.cancelled && !day(b.timeline[BookingStatus.accepted] ?? b.timeline[BookingStatus.delivered] ?? today).isBefore(from)) b,
    ];
    final delivered = [for (final b in recent) if (b.status == BookingStatus.delivered && !day(EarningsSummary.deliveredAt(b)).isBefore(from)) b];
    final exp = ExpenseSummary.lastDays(expenses, now, window);

    final rows = <FleetVehicleStats>[];
    for (final v in vehicles) {
      final days = <DateTime>{};
      for (final b in recent.where((b) => b.vehicleId == v.id)) {
        final start = day(b.timeline[BookingStatus.pickedUp] ?? b.timeline[BookingStatus.accepted] ?? today);
        final endRaw = b.status == BookingStatus.delivered ? EarningsSummary.deliveredAt(b) : now;
        final end = day(endRaw);
        for (var d = start.isBefore(from) ? from : start; !d.isAfter(end) && !d.isAfter(today); d = d.add(const Duration(days: 1))) {
          days.add(d);
        }
      }
      rows.add(FleetVehicleStats(
        vehicle: v,
        daysOnRoad: days.length,
        revenuePaise: delivered.where((b) => b.vehicleId == v.id).fold(0, (a, b) => a + (b.billAmountPaise ?? 0)),
        expensesPaise: ExpenseSummary.total(exp.where((e) => e.vehicleId == v.id)),
      ));
    }
    rows.sort((a, b) => b.netPaise.compareTo(a.netPaise));

    final perCustomer = <String, int>{};
    for (final b in delivered) {
      perCustomer[b.customerId] = (perCustomer[b.customerId] ?? 0) + 1;
    }
    final top = [for (final e in perCustomer.entries) CustomerTrips(e.key, e.value)]..sort((a, b) => b.trips.compareTo(a.trips));
    final perDriver = <String, int>{};
    for (final b in delivered) {
      perDriver[b.driverId] = (perDriver[b.driverId] ?? 0) + 1;
    }

    return FleetAnalytics(
      vehicles: rows,
      revenuePaise: rows.fold(0, (a, r) => a + r.revenuePaise),
      expensesPaise: rows.fold(0, (a, r) => a + r.expensesPaise),
      maintenanceDue: vehicles.where((v) => v.serviceDue(now) || v.tyreDue(now) || v.docsExpiringWithin(now).isNotEmpty).length,
      customersServed: perCustomer.length,
      repeatCustomers: perCustomer.values.where((n) => n > 1).length,
      topCustomers: top.take(3).toList(),
      tripsPerDriver: perDriver,
      driverNames: {for (final id in perDriver.keys) id: names[id] ?? ''},
    );
  }
}
