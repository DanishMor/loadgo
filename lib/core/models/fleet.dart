import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import 'booking.dart';
import 'earnings.dart';
import 'vehicle.dart';

/// `fleet_invites/{ownerId}_{phoneDigits}`: a transporter invites a driver
/// by phone number.
class FleetInvite {
  final String id;
  final String ownerId;
  final String ownerName;
  final String phone;
  final String status;
  final DateTime? createdAt;

  const FleetInvite({required this.id, required this.ownerId, this.ownerName = '', required this.phone, required this.status, this.createdAt});

  static const pending = 'pending';
  static const accepted = 'accepted';
  static const declined = 'declined';
  static const cancelled = 'cancelled';

  /// The document id for an invite from [ownerId] to [phone] (+91xxxxxxxxxx).
  static String idFor(String ownerId, String phone) => '${ownerId}_${phone.replaceAll('+', '')}';

  /// Normalises what a person typed (10 digits, with or without +91 / 0).
  static String? normalisePhone(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    return RegExp(r'^[6-9][0-9]{9}$').hasMatch(d) ? '+91$d' : null;
  }

  factory FleetInvite.fromDoc(String id, Map<String, dynamic> d) => FleetInvite(
        id: id,
        ownerId: d['ownerId'] as String? ?? '',
        ownerName: d['ownerName'] as String? ?? '',
        phone: d['phone'] as String? ?? '',
        status: d['status'] as String? ?? pending,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// `fleet_members/{ownerId}_{driverUid}`: a driver who joined a fleet.
class FleetMember {
  final String id;
  final String ownerId;
  final String ownerName;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final bool active;

  /// The driver's licence expiry, shared by the driver with this fleet (null = not shared).
  final DateTime? licenceExpiry;

  const FleetMember({required this.id, required this.ownerId, this.ownerName = '', required this.driverId, this.driverName = '', this.driverPhone = '', required this.active, this.licenceExpiry});

  factory FleetMember.fromDoc(String id, Map<String, dynamic> d) => FleetMember(
        id: id,
        ownerId: d['ownerId'] as String? ?? '',
        ownerName: d['ownerName'] as String? ?? '',
        driverId: d['driverId'] as String? ?? '',
        driverName: d['driverName'] as String? ?? '',
        driverPhone: d['driverPhone'] as String? ?? '',
        active: d['active'] == true,
        licenceExpiry: (d['licenceExpiry'] as Timestamp?)?.toDate(),
      );
}

/// One vehicle's line on the fleet dashboard.
class FleetVehicleRow {
  final Vehicle vehicle;
  final String? driverName;
  final int activeTrips;
  final int deliveredTrips;

  /// Money from delivered trips on this vehicle (paise; paid > agreed >
  /// estimate). A record, not a payout.
  final int earningsPaise;

  const FleetVehicleRow({required this.vehicle, this.driverName, required this.activeTrips, required this.deliveredTrips, required this.earningsPaise});

  bool get idle => vehicle.isActive && vehicle.availability == VehicleAvailability.available && activeTrips == 0;
}

/// The fleet dashboard figures, worked out from the owner's vehicles, the
/// bookings carrying their `fleetOwnerId` (and any trips they drive
/// themselves), and the active members.
class FleetSummary {
  final List<FleetVehicleRow> vehicles;
  final int totalEarningsPaise;
  final int todayEarningsPaise;
  final int activeTrips;
  final int idleVehicles;
  final int activeDrivers;

  const FleetSummary({
    required this.vehicles,
    required this.totalEarningsPaise,
    required this.todayEarningsPaise,
    required this.activeTrips,
    required this.idleVehicles,
    required this.activeDrivers,
  });

  factory FleetSummary.from({
    required Iterable<Vehicle> vehicles,
    required Iterable<Booking> bookings,
    required Iterable<FleetMember> members,
    required DateTime now,
  }) {
    final names = {for (final m in members) if (m.active) m.driverId: m.driverName};
    final startOfDay = DateTime(now.year, now.month, now.day);
    final rows = <FleetVehicleRow>[];
    var total = 0, today = 0, active = 0, idle = 0;
    for (final v in vehicles) {
      final mine = bookings.where((b) => b.vehicleId == v.id).toList();
      final live = mine.where((b) => b.isActive).length;
      final done = mine.where((b) => b.status == BookingStatus.delivered).toList();
      final money = done.fold<int>(0, (a, b) => a + (b.billAmountPaise ?? 0));
      for (final b in done) {
        if (!EarningsSummary.deliveredAt(b).isBefore(startOfDay)) today += b.billAmountPaise ?? 0;
      }
      total += money;
      active += live;
      final row = FleetVehicleRow(
        vehicle: v,
        driverName: v.assignedDriverId == null ? null : names[v.assignedDriverId],
        activeTrips: live,
        deliveredTrips: done.length,
        earningsPaise: money,
      );
      if (row.idle) idle++;
      rows.add(row);
    }
    rows.sort((a, b) => b.earningsPaise.compareTo(a.earningsPaise));
    return FleetSummary(
      vehicles: rows,
      totalEarningsPaise: total,
      todayEarningsPaise: today,
      activeTrips: active,
      idleVehicles: idle,
      activeDrivers: names.length,
    );
  }
}
