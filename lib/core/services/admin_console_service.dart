import 'package:cloud_firestore/cloud_firestore.dart';

import '../matching/supply_demand.dart';
import '../models/load.dart';
import '../models/vehicle.dart';
import 'user_service.dart';
import '../network/with_retry.dart';
import '../constants/logistics.dart';
import '../admin/admin_export.dart';
import '../models/booking.dart';
import 'audit_service.dart';
import '../admin/staff_roles.dart';
import 'backend.dart';
import 'load_service.dart';

/// Counters shown on the admin dashboard.
class AdminCounters {
  final int users;
  final int drivers;
  final Map<String, int> loadsByStatus;
  final Map<String, int> bookingsByStatus;

  /// Sum of the billed amount (paise) over delivered bookings.
  final int deliveredFarePaise;

  const AdminCounters({
    required this.users,
    required this.drivers,
    required this.loadsByStatus,
    required this.bookingsByStatus,
    required this.deliveredFarePaise,
  });
}

/// Totals shown on Admin > System health.
class HealthCounts {
  final int users;
  final int loads;
  final int bookings;
  final int openTickets;
  final int pendingDeletions;
  const HealthCounts({required this.users, required this.loads, required this.bookings, required this.openTickets, required this.pendingDeletions});
}

class ReassignException implements Exception {
  final String reason;
  ReassignException(this.reason);

  @override
  String toString() => 'ReassignException($reason)';
}

/// Everything the admin screens read or write beyond what the feature
/// services already offer. Rules (admins/{uid}) are the real gate; the app
/// only hides the entry for non-admins.
class AdminConsoleService {
  AdminConsoleService._();

  static FirebaseFirestore get _db => Backend.db;

  static const listLimit = 100;

  /// Whether the signed-in user is in the `admins` allowlist.
  static Future<bool> isAdmin() async {
    final uid = Backend.uid;
    if (uid == null) return false;
    try {
      return (await _db.collection('admins').doc(uid).get()).exists;
    } catch (_) {
      return false;
    }
  }

  /// The signed-in admin's staff role (BE7); super when the field is missing.
  static Future<String> staffRole() async {
    final uid = Backend.uid;
    if (uid == null) return StaffRole.superAdmin;
    try {
      return StaffRole.normalise((await _db.collection('admins').doc(uid).get()).data()?['role']);
    } catch (_) {
      return StaffRole.superAdmin;
    }
  }

  // ---- users ----

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> users({int limit = 300}) async =>
      (await _db.collection('users').limit(limit).get()).docs;

  /// CSV of up to [limit] users with phone and e-mail masked (Admin > Users > Export).
  static Future<String> usersCsv({int limit = 1000}) async {
    final docs = (await _db.collection('users').limit(limit).get()).docs;
    return AdminExport.usersCsv([for (final d in docs) (d.id, d.data())]);
  }

  /// CSV of the newest bookings, optionally of one [status].
  static Future<String> bookingsCsv({String? status, int limit = 1000}) async {
    final all = await recentBookings(limit: limit);
    return AdminExport.bookingsCsv(status == null ? all : all.where((b) => b.status == status));
  }

  /// Case-insensitive match on name, driver name, phone or uid.
  static bool userMatches(Map<String, dynamic> data, String uid, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [uid, data['name'], data['driverName'], data['phone'], data['email'], data['companyName']]
        .any((v) => v is String && v.toLowerCase().contains(q));
  }

  // ---- vehicles ----

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchVehicles() =>
      _db.collection('vehicles').limit(listLimit).snapshots().map((s) => s.docs);

  /// Suspend or lift a suspension (admin only per rules).
  static Future<void> setVehicleAvailability(String vehicleId, String availability) {
    assert(VehicleAvailability.all.contains(availability));
    return _db.collection('vehicles').doc(vehicleId).update({
      'availability': availability,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Lets a vehicle with expired papers work for [days] days: sets the
  /// override and lifts the document suspension (admin only per rules).
  static Future<void> overrideVehicleDocs(String vehicleId, {int days = 7}) {
    return _db.collection('vehicles').doc(vehicleId).update({
      'availability': VehicleAvailability.available,
      'docOverrideUntil': Timestamp.fromDate(DateTime.now().add(Duration(days: days))),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Lets a driver with an expired licence accept loads for [days] days.
  static Future<void> overrideLicence(String userId, {int days = 7}) {
    return _db.collection('users').doc(userId).update({
      'docOverrideUntil': Timestamp.fromDate(DateTime.now().add(Duration(days: days))),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- loads / bookings ----

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchLoads({String? status}) {
    Query<Map<String, dynamic>> q = _db.collection('loads');
    if (status != null) q = q.where('status', isEqualTo: status);
    return q.limit(listLimit).snapshots().map((s) => s.docs);
  }

  static Stream<List<Booking>> watchBookings({String? status}) {
    Query<Map<String, dynamic>> q = _db.collection('bookings');
    if (status != null) q = q.where('status', isEqualTo: status);
    return q.limit(listLimit).snapshots().map((s) => s.docs.map(Booking.fromDoc).toList());
  }

  /// Moves a booking that has not been picked up yet to the driver who owns
  /// the vehicle numbered [vehicleNumber]. Copies that driver's details to
  /// the booking, re-points the load, swaps vehicle availability and writes
  /// an audit event, all in one batch.
  static Future<void> reassignDriver(Booking booking, String vehicleNumber) async {
    if (!const [BookingStatus.accepted, BookingStatus.driverArriving, BookingStatus.loading].contains(booking.status)) {
      throw ReassignException('status');
    }
    final number = vehicleNumber.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final found = await _db.collection('vehicles').where('number', isEqualTo: number).limit(1).get();
    if (found.docs.isEmpty) throw ReassignException('vehicle');
    final vehicle = found.docs.first;
    final v = vehicle.data();
    final ownerId = v['ownerId'] as String? ?? '';
    if (ownerId == booking.driverId || ownerId.isEmpty) throw ReassignException('same_driver');
    if (v['status'] != 'active' || (v['availability'] ?? VehicleAvailability.available) != VehicleAvailability.available) {
      throw ReassignException('unavailable');
    }
    final owner = (await _db.collection('users').doc(ownerId).get()).data() ?? const {};
    final batch = _db.batch();
    batch.update(_db.collection('bookings').doc(booking.id), {
      'driverId': ownerId,
      'vehicleId': vehicle.id,
      'vehicleNumber': v['number'],
      'vehicleType': v['type'],
      'driverName': owner['driverName'] ?? owner['name'] ?? '',
      'driverPhone': owner['phone'] ?? '',
      'reassignedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('loads').doc(booking.loadId), {'driverId': ownerId});
    batch.update(_db.collection('vehicles').doc(vehicle.id), {
      'availability': VehicleAvailability.onTrip,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('vehicles').doc(booking.vehicleId), {
      'availability': VehicleAvailability.available,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.reassign,
        targetId: ownerId,
        bookingId: booking.id,
        loadId: booking.loadId,
        data: {'fromDriverId': booking.driverId, 'toDriverId': ownerId, 'vehicleNumber': v['number']});
    await batch.commit();
  }

  // ---- SOS and reports ----

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchSos() =>
      _db.collection('sos_alerts').limit(listLimit).snapshots().map((s) => s.docs);

  static Future<void> setSosStatus(String id, String status, {String note = ''}) {
    assert(const ['open', 'acknowledged', 'resolved'].contains(status));
    return _db.collection('sos_alerts').doc(id).update({
      'status': status,
      'handledBy': Backend.requireUid(),
      'handledAt': FieldValue.serverTimestamp(),
      if (note.trim().isNotEmpty) 'adminNote': note.trim(),
    });
  }

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchReports() =>
      _db.collection('reports').limit(listLimit).snapshots().map((s) => s.docs);

  static Future<void> resolveReport(String id, {String note = ''}) => _db.collection('reports').doc(id).update({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': Backend.requireUid(),
        if (note.trim().isNotEmpty) 'adminNote': note.trim(),
      });

  // ---- tickets ----

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchTickets() =>
      _db.collection('tickets').limit(listLimit).snapshots().map((s) => s.docs);

  static Future<void> updateTicket(String id, {String? status, String? priority}) => _db.collection('tickets').doc(id).update({
        'status': ?status,
        'priority': ?priority,
        'assignedTo': Backend.requireUid(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ---- deletion requests ----

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchDeletionRequests() =>
      _db.collection('deletion_requests').limit(listLimit).snapshots().map((s) => s.docs);

  static Future<void> setDeletionStatus(String userId, String status) {
    assert(const ['pending', 'done', 'rejected'].contains(status));
    return _db.collection('deletion_requests').doc(userId).update({
      'status': status,
      'handledBy': Backend.requireUid(),
      'handledAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- config ----

  /// Adds `pickupGeohash` to older loads (see docs/MIGRATIONS.md).
  static Future<int> backfillPickupGeohash() => LoadService.backfillPickupGeohash();

  static Future<Map<String, dynamic>?> readConfig(String docId) async =>
      (await _db.collection('config').doc(docId).get()).data();

  /// Saves a config document and records who changed which top-level keys
  /// in the audit log (same batch), so pricing and rule edits are traceable.
  static Future<void> writeConfig(String docId, Map<String, dynamic> data) async {
    final ref = _db.collection('config').doc(docId);
    final before = (await ref.get()).data() ?? const <String, dynamic>{};
    final changed = <String>{
      for (final k in {...before.keys, ...data.keys})
        if (k != 'updatedAt' && '${before[k]}' != '${data[k]}') k,
    }.toList()
      ..sort();
    final batch = _db.batch();
    batch.set(ref, {...data, 'updatedAt': FieldValue.serverTimestamp()});
    AuditService.inBatch(batch, AuditType.configChange, targetId: docId, data: {'doc': docId, 'changedKeys': changed});
    await batch.commit();
  }

  /// The latest audit events (admins only), newest first.
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchAudit({int limit = 100}) =>
      _db.collection('audit_events').orderBy('createdAt', descending: true).limit(limit).snapshots().map((s) => s.docs);

  // ---- analytics ----

  /// The newest bookings (by creation time) for the trend charts.
  static Future<List<Booking>> recentBookings({int limit = 1000}) async {
    final snap = await _db.collection('bookings').orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map(Booking.fromDoc).toList();
  }

  static Future<int> _count(Query<Map<String, dynamic>> q) async => (await q.count().get()).count ?? 0;

  /// Document counts for the health screen.
  /// Open loads against free trucks (newest [limit] of each; drivers with a
  /// saved position place their truck, an assigned fleet driver wins over the owner).
  static Future<SupplyDemand> supplyDemand({int limit = 500}) => withRetry(() async {
        final loads = await _db.collection('loads').where('status', isEqualTo: LoadStatus.open).limit(limit).get();
        final vehicles = await _db.collection('vehicles').where('availability', isEqualTo: VehicleAvailability.available).limit(limit).get();
        final users = await _db.collection('users').where('role', isEqualTo: 'driver').limit(limit).get();
        final spots = {for (final u in users.docs) u.id: UserService.lastLocationOf(u.data())};
        return SupplyDemand.compute(
          [for (final d in loads.docs) Load.fromDoc(d)],
          [for (final d in vehicles.docs) Vehicle.fromDoc(d)],
          (v) => spots[v.assignedDriverId] ?? spots[v.ownerId],
        );
      });

  static Future<HealthCounts> health() => withRetry(_health);

  static Future<HealthCounts> _health() async {
    final r = await Future.wait([
      _count(_db.collection('users')),
      _count(_db.collection('loads')),
      _count(_db.collection('bookings')),
      _count(_db.collection('tickets').where('status', whereIn: ['open', 'in_progress'])),
      _count(_db.collection('deletion_requests').where('status', isEqualTo: 'pending')),
    ]);
    return HealthCounts(users: r[0], loads: r[1], bookings: r[2], openTickets: r[3], pendingDeletions: r[4]);
  }

  static Future<AdminCounters> counters() async {
    final loadStatuses = [LoadStatus.open, LoadStatus.matched, LoadStatus.closed];
    final bookingStatuses = [...BookingStatus.flow, BookingStatus.cancelled];
    final users = _db.collection('users');
    final results = await Future.wait([
      _count(users),
      _count(users.where('roles', arrayContains: 'driver')),
      for (final s in loadStatuses) _count(_db.collection('loads').where('status', isEqualTo: s)),
      for (final s in bookingStatuses) _count(_db.collection('bookings').where('status', isEqualTo: s)),
    ]);
    final delivered = await _db.collection('bookings').where('status', isEqualTo: BookingStatus.delivered).limit(1000).get();
    var sum = 0;
    for (final d in delivered.docs) {
      sum += Booking.fromDoc(d).billAmountPaise ?? 0;
    }
    return AdminCounters(
      users: results[0],
      drivers: results[1],
      loadsByStatus: {for (var i = 0; i < loadStatuses.length; i++) loadStatuses[i]: results[2 + i]},
      bookingsByStatus: {
        for (var i = 0; i < bookingStatuses.length; i++) bookingStatuses[i]: results[2 + loadStatuses.length + i],
      },
      deliveredFarePaise: sum,
    );
  }
}
