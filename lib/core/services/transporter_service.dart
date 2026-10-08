import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/fleet.dart';
import '../models/vehicle.dart';
import '../transporter/transporter_logic.dart';
import 'audit_service.dart';
import 'backend.dart';

/// Thrown by [TransporterService.assign]. [reason] is one of the values of
/// [assignmentProblem] (`status`, `not_member`, `vehicle`, `busy`, `papers`,
/// `capacity`, `same`).
class AssignException implements Exception {
  final String reason;
  const AssignException(this.reason);

  @override
  String toString() => 'AssignException($reason)';
}

/// Transporter (Task 67): profile, attached vehicles, assigning a vehicle and
/// driver to a company booking, and the private books. Records only; no
/// money moves. TODO(functions): the assign audit line could be written by a
/// trigger so a client cannot skip it.
class TransporterService {
  TransporterService._();

  static FirebaseFirestore get _db => Backend.db;

  // ---- profile ----

  static Future<TransporterProfile> loadProfile() async {
    final uid = Backend.requireUid();
    return TransporterProfile.fromUser((await _db.collection('users').doc(uid).get()).data());
  }

  /// Saves the editable part of the company profile (PAN stays as it is: it is
  /// locked by the identity index and changed only through support).
  static Future<void> updateProfile(TransporterProfile p) async {
    final uid = Backend.requireUid();
    final bad = [for (final e in p.errors()) if (e != 'pan') e];
    if (bad.isNotEmpty) throw ArgumentError.value(bad.join(','), 'profile');
    final ref = _db.collection('users').doc(uid);
    final before = (await ref.get()).data();
    final pan = TransporterProfile.fromUser(before).pan;
    await ref.update({
      'companyName': p.company.trim(),
      'fleet': TransporterProfile(pan: pan, officeCity: p.officeCity, routes: p.routes, vehicleTypes: p.vehicleTypes, vehicleCount: p.vehicleCount).toFleetMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- vehicles ----

  /// Vehicles members attached to this transporter.
  static Stream<List<Vehicle>> watchAttached() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('vehicles').where('attachedTo', isEqualTo: uid).snapshots().map((s) => s.docs.map(Vehicle.fromDoc).toList());
  }

  /// The signed-in driver attaches [vehicleId] to [transporterId] (they must
  /// be an active member: the accepted invite is the consent) or detaches it
  /// with null.
  static Future<void> setAttached(String vehicleId, String? transporterId) => _db.collection('vehicles').doc(vehicleId).update({
        'attachedTo': transporterId ?? FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ---- assigning ----

  /// Picks [vehicle] and the member [driver] to run [booking] (first
  /// assignment or a reassignment). The old vehicle becomes available again
  /// and the new one is marked on a trip, and an `assign` audit event records
  /// who changed what.
  static Future<void> assign({required Booking booking, required Vehicle vehicle, required FleetMember driver, DateTime? now}) async {
    final uid = Backend.requireUid();
    final problem = assignmentProblem(booking: booking, transporterId: uid, vehicle: vehicle, member: driver, now: now ?? DateTime.now());
    if (problem != null) throw AssignException(problem);
    final previousVehicle = booking.assignedVehicleId ?? booking.vehicleId;
    final batch = _db.batch();
    batch.update(_db.collection('bookings').doc(booking.id), {
      'assignedDriverId': driver.driverId,
      'assignedDriverName': driver.driverName,
      'assignedVehicleId': vehicle.id,
      'assignedVehicleNumber': vehicle.number,
      'assignedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (previousVehicle != vehicle.id) {
      batch.update(_db.collection('vehicles').doc(previousVehicle), {'availability': VehicleAvailability.available, 'updatedAt': FieldValue.serverTimestamp()});
      batch.update(_db.collection('vehicles').doc(vehicle.id), {'availability': VehicleAvailability.onTrip, 'updatedAt': FieldValue.serverTimestamp()});
    }
    AuditService.inBatch(batch, AuditType.assign, bookingId: booking.id, targetId: driver.driverId, data: {
      'vehicleId': vehicle.id,
      'vehicleNumber': vehicle.number,
      if (booking.assignedDriverId != null) 'previousDriverId': booking.assignedDriverId,
      'previousVehicleId': previousVehicle,
      'reassign': booking.assignedDriverId != null,
    });
    await batch.commit();
  }

  /// Bookings the assigned driver runs for a transporter.
  static Stream<List<Booking>> watchAssignedToMe() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('bookings').where('assignedDriverId', isEqualTo: uid).snapshots().map((s) => s.docs.map(Booking.fromDoc).toList());
  }

  // ---- books ----

  static CollectionReference<Map<String, dynamic>> get _books => _db.collection('transporter_accounts');

  static Stream<List<TripAccount>> watchBooks() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _books.where('ownerId', isEqualTo: uid).snapshots().map((s) => [for (final d in s.docs) TripAccount.fromMap(d.id, d.data())]);
  }

  /// Creates or updates the books line of [booking] (record only).
  static Future<void> saveAccount({
    required Booking booking,
    String partyName = '',
    required int revenuePaise,
    required int driverPayPaise,
    required int otherCostPaise,
    required int receivedPaise,
  }) async {
    final uid = Backend.requireUid();
    for (final v in [revenuePaise, driverPayPaise, otherCostPaise, receivedPaise]) {
      if (v < 0 || v > 100000000) throw ArgumentError.value(v, 'paise');
    }
    final ref = _books.doc(booking.id);
    final lines = {
      'partyName': partyName.trim().length > 80 ? partyName.trim().substring(0, 80) : partyName.trim(),
      'revenuePaise': revenuePaise,
      'driverPayPaise': driverPayPaise,
      'otherCostPaise': otherCostPaise,
      'receivedPaise': receivedPaise,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if ((await ref.get()).exists) {
      await ref.update(lines);
    } else {
      await ref.set({'ownerId': uid, 'bookingId': booking.id, 'partyId': booking.customerId, ...lines});
    }
  }
}
