import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/fleet.dart';
import '../models/vehicle.dart';
import '../transporter/transporter_logic.dart';
import 'fleet_logic.dart';

/// One screen of a transporter's operations (MASTER-6 Task 28): trips by
/// status, vehicle use, trips per driver and what each party still owes.
class TransporterBoard {
  /// Trips by status: running ones now, delivered and cancelled in the last 30 days.
  final Map<String, int> tripsByStatus;

  /// Average share of the last 30 days the vehicles were on the road, 0..1.
  final double utilisation;

  /// The least used vehicles, most idle first (up to 3).
  final List<FleetVehicleStats> leastUsed;

  /// Delivered trips in 30 days per driver (name or id), most first (up to 5).
  final List<({String driver, int trips})> drivers;

  /// Parties that still owe, largest first (up to 5), and the total due.
  final List<PartyBalance> parties;
  final int totalDuePaise;

  const TransporterBoard({
    required this.tripsByStatus,
    required this.utilisation,
    required this.leastUsed,
    required this.drivers,
    required this.parties,
    required this.totalDuePaise,
  });

  /// Statuses shown, in the order of a trip's life.
  static const statusOrder = [...BookingStatus.flow, BookingStatus.cancelled];

  static TransporterBoard compute({
    required Iterable<Vehicle> vehicles,
    required Iterable<Booking> bookings,
    required Iterable<FleetMember> members,
    required Iterable<TripAccount> accounts,
    required DateTime now,
  }) {
    final analytics = FleetAnalytics.from(vehicles: vehicles, bookings: bookings, expenses: const [], members: members, now: now);
    final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: FleetAnalytics.window - 1));
    final counts = {for (final s in statusOrder) s: 0};
    for (final b in bookings) {
      if (!counts.containsKey(b.status)) continue;
      final finished = b.status == BookingStatus.delivered || b.status == BookingStatus.cancelled;
      if (finished) {
        final at = b.timeline[b.status] ?? b.timeline[BookingStatus.accepted];
        if (at != null && DateTime(at.year, at.month, at.day).isBefore(from)) continue;
      }
      counts[b.status] = counts[b.status]! + 1;
    }
    final used = [...analytics.vehicles]..sort((a, b) => a.daysOnRoad.compareTo(b.daysOnRoad));
    final drivers = [
      for (final e in analytics.tripsPerDriver.entries) (driver: (analytics.driverNames[e.key] ?? '').isEmpty ? e.key : analytics.driverNames[e.key]!, trips: e.value),
    ]..sort((a, b) => b.trips.compareTo(a.trips));
    final books = TransporterBooks.from(accounts);
    final owing = [for (final p in books.parties) if (p.duePaise > 0) p];
    return TransporterBoard(
      tripsByStatus: counts,
      utilisation: analytics.utilisation,
      leastUsed: used.take(3).toList(),
      drivers: drivers.take(5).toList(),
      parties: owing.take(5).toList(),
      totalDuePaise: owing.fold(0, (a, p) => a + p.duePaise),
    );
  }
}
