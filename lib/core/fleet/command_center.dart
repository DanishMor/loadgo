import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/offer.dart';
import '../models/vehicle.dart';

/// E23: what a vehicle is doing right now on the transporter's status board.
enum VehicleState { onTrip, assigned, available, blocked, off }

class VehicleNow {
  final Vehicle vehicle;
  final VehicleState state;

  /// The running booking when [state] is onTrip or assigned.
  final Booking? booking;
  const VehicleNow(this.vehicle, this.state, [this.booking]);
}

/// Things that need the transporter today, most urgent first.
enum AlertKind { papersExpired, counterOffer, papersSoon, idleTruck, partyDue }

class FleetAlert {
  final AlertKind kind;

  /// What it is about: a vehicle number, a route or a party name.
  final String subject;
  final int count;
  const FleetAlert(this.kind, this.subject, [this.count = 0]);
}

/// E23 (flag fleetCommand): the transporter's command center, worked out on the phone from the lists the dashboard
/// already listens to plus the newest bids.
class CommandCenter {
  final List<VehicleNow> board;
  final List<Offer> pendingBids;
  final List<FleetAlert> alerts;
  const CommandCenter({required this.board, required this.pendingBids, required this.alerts});

  Map<VehicleState, int> get counts => {for (final s in VehicleState.values) s: board.where((v) => v.state == s).length};

  static const _running = [BookingStatus.driverArriving, BookingStatus.loading, BookingStatus.pickedUp, BookingStatus.inTransit, BookingStatus.unloading];

  static CommandCenter compute({
    required Iterable<Vehicle> vehicles,
    required Iterable<Booking> bookings,
    required Iterable<Offer> bids,
    required Map<String, int> idleDays,
    required List<({String name, int duePaise})> dues,
    required DateTime now,
    int idleAlertDays = 7,
  }) {
    final open = [for (final b in bookings) if (b.status != BookingStatus.delivered && b.status != BookingStatus.cancelled) b];
    Booking? runningFor(Vehicle v) => open.where((b) => b.vehicleId == v.id && _running.contains(b.status)).firstOrNull;
    Booking? assignedFor(Vehicle v) => open.where((b) => b.vehicleId == v.id && b.status == BookingStatus.accepted).firstOrNull;

    final board = <VehicleNow>[];
    for (final v in vehicles) {
      final run = runningFor(v);
      final next = assignedFor(v);
      board.add(switch (v) {
        _ when run != null => VehicleNow(v, VehicleState.onTrip, run),
        _ when !v.isActive => VehicleNow(v, VehicleState.off),
        _ when v.papersBlocked(now) => VehicleNow(v, VehicleState.blocked),
        _ when next != null => VehicleNow(v, VehicleState.assigned, next),
        _ => VehicleNow(v, VehicleState.available),
      });
    }
    board.sort((a, b) => a.state.index != b.state.index ? a.state.index.compareTo(b.state.index) : a.vehicle.number.compareTo(b.vehicle.number));

    final pending = [for (final o in bids) if (o.isOpen) o];
    final alerts = <FleetAlert>[
      for (final v in vehicles)
        if (v.expiredDocs(now).isNotEmpty) FleetAlert(AlertKind.papersExpired, v.number, v.expiredDocs(now).length),
      for (final o in pending)
        if (o.status == OfferStatus.countered) FleetAlert(AlertKind.counterOffer, '${o.pickup} → ${o.drop}'),
      for (final v in vehicles)
        if (v.expiredDocs(now).isEmpty && v.docsExpiringWithin(now).isNotEmpty) FleetAlert(AlertKind.papersSoon, v.number, v.docsExpiringWithin(now).length),
      for (final v in vehicles)
        if (v.isActive && runningFor(v) == null && (idleDays[v.id] ?? 0) >= idleAlertDays) FleetAlert(AlertKind.idleTruck, v.number, idleDays[v.id]!),
      for (final d in dues)
        if (d.duePaise > 0) FleetAlert(AlertKind.partyDue, d.name, d.duePaise),
    ]..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return CommandCenter(board: board, pendingBids: pending, alerts: alerts.take(12).toList());
  }
}
