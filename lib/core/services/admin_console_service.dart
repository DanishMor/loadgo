import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../analytics/unit_economics.dart';
import 'server_clock.dart';
import '../admin/dispatch.dart';
import '../admin/pilot_control.dart';
import '../admin/pilot_cohorts.dart';
import '../pilot/reuse_survey.dart';
import '../admin/pilot_report.dart';
import '../admin/pilot_funnel.dart';
import '../matching/supply_demand.dart';
import '../models/ledger_entry.dart';
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

  /// Live check of `admins/{uid}` (Task 69): emits false while signed out,
  /// on any error, and the moment the document goes away.
  static Stream<bool> isAdminStream() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(false);
    return _db.collection('admins').doc(uid).snapshots().map((d) => d.exists).transform(
          StreamTransformer<bool, bool>.fromHandlers(handleError: (e, st, sink) => sink.add(false)),
        );
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

  /// One admin write plus its `user_action` audit event in the same batch
  /// (MASTER-5 Task 5): every admin change is traceable. [what] names the
  /// action, [targetId] the document it touched; [extra] holds small values.
  static Future<void> _audited(String what, String targetId, DocumentReference<Map<String, dynamic>> ref, Map<String, Object?> change, Map<String, Object?> extra) {
    final batch = _db.batch();
    batch.update(ref, change);
    AuditService.inBatch(batch, AuditType.userAction, targetId: targetId, data: {'action': what, 'collection': ref.parent.id, ...extra});
    return batch.commit();
  }

  // ---- vehicles ----

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchVehicles() =>
      _db.collection('vehicles').limit(listLimit).snapshots().map((s) => s.docs);

  /// Suspend or lift a suspension (admin only per rules).
  static Future<void> setVehicleAvailability(String vehicleId, String availability) {
    assert(VehicleAvailability.all.contains(availability));
    return _audited('vehicle_availability', vehicleId, _db.collection('vehicles').doc(vehicleId), {
      'availability': availability,
      'updatedAt': FieldValue.serverTimestamp(),
    }, {'availability': availability});
  }

  /// Lets a vehicle with expired papers work for [days] days: sets the
  /// override and lifts the document suspension (admin only per rules).
  static Future<void> overrideVehicleDocs(String vehicleId, {int days = 7}) {
    return _audited('vehicle_doc_override', vehicleId, _db.collection('vehicles').doc(vehicleId), {
      'availability': VehicleAvailability.available,
      'docOverrideUntil': Timestamp.fromDate(DateTime.now().add(Duration(days: days))),
      'updatedAt': FieldValue.serverTimestamp(),
    }, {'days': days});
  }

  /// Lets a driver with an expired licence accept loads for [days] days.
  static Future<void> overrideLicence(String userId, {int days = 7}) {
    return _audited('licence_override', userId, _db.collection('users').doc(userId), {
      'docOverrideUntil': Timestamp.fromDate(DateTime.now().add(Duration(days: days))),
      'updatedAt': FieldValue.serverTimestamp(),
    }, {'days': days});
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
      'driverPhone': '',
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
    return _audited('sos_status', id, _db.collection('sos_alerts').doc(id), {
      'status': status,
      'handledBy': Backend.requireUid(),
      'handledAt': FieldValue.serverTimestamp(),
      if (note.trim().isNotEmpty) 'adminNote': note.trim(),
    }, {'status': status});
  }

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchReports() =>
      _db.collection('reports').limit(listLimit).snapshots().map((s) => s.docs);

  static Future<void> resolveReport(String id, {String note = ''}) => _audited('report_resolve', id, _db.collection('reports').doc(id), {
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': Backend.requireUid(),
        if (note.trim().isNotEmpty) 'adminNote': note.trim(),
      }, const {});

  // ---- tickets ----

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchTickets() =>
      _db.collection('tickets').limit(listLimit).snapshots().map((s) => s.docs);

  static Future<void> updateTicket(String id, {String? status, String? priority}) => _audited('ticket_update', id, _db.collection('tickets').doc(id), {
        'status': ?status,
        'priority': ?priority,
        'assignedTo': Backend.requireUid(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, {'status': ?status, 'priority': ?priority});

  // ---- deletion requests ----

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchDeletionRequests() =>
      _db.collection('deletion_requests').limit(listLimit).snapshots().map((s) => s.docs);

  static Future<void> setDeletionStatus(String userId, String status) {
    assert(const ['pending', 'done', 'rejected'].contains(status));
    return _audited('deletion_status', userId, _db.collection('deletion_requests').doc(userId), {
      'status': status,
      'handledBy': Backend.requireUid(),
      'handledAt': FieldValue.serverTimestamp(),
    }, {'status': status});
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

  /// Waitlist entries (newest first).
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchWaitlist() =>
      _db.collection('waitlist').orderBy('createdAt', descending: true).limit(listLimit).snapshots().map((x) => x.docs);

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
  static Future<EconomicsCosts> economicsCosts() async =>
      EconomicsCosts.fromMap((await withRetry(() => _db.collection('config').doc('economics').get())).data());

  static Future<void> saveEconomicsCosts(EconomicsCosts c) => writeConfig('economics', c.toMap());

  /// Last [days] days: bookings (newest 1000), platform commission lines of
  /// the driver ledger (newest 1000 lines) and the typed costs.
  static Future<UnitEconomics> unitEconomics({int days = 30, DateTime? now}) => withRetry(() async {
        final at = now ?? DateTime.now();
        final since = DateTime(at.year, at.month, at.day).subtract(Duration(days: days - 1));
        final bookings = await recentBookings();
        final snap = await _db
            .collection('ledger')
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
            .orderBy('createdAt', descending: true)
            .limit(1000)
            .get();
        final lines = <CommissionLine>[
          for (final d in snap.docs)
            if (d.data()['type'] == LedgerType.platformCommission && d.data()['createdAt'] is Timestamp)
              (at: (d.data()['createdAt'] as Timestamp).toDate(), paise: -((d.data()['amountPaise'] as num?)?.round() ?? 0)),
        ];
        return UnitEconomics.compute(bookings, lines, costs: await economicsCosts(), now: at, days: days);
      });

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

  /// Customers, drivers and transporters on the way to a first delivery. Reads
  /// the newest [limit] users of each role, loads and bookings (about 2,000
  /// reads, once per press).
  static Future<PilotFunnel> pilotFunnel({int limit = 500}) => withRetry(() async {
        final users = <(String, Map<String, dynamic>)>[];
        for (final role in ['customer', 'driver', 'fleet']) {
          final snap = await _db.collection('users').where('role', isEqualTo: role).limit(limit).get();
          users.addAll([for (final d in snap.docs) (d.id, d.data())]);
        }
        final loads = await _db.collection('loads').limit(limit).get();
        final bookings = await _db.collection('bookings').limit(limit).get();
        return PilotFunnel.compute(
          users: users,
          loadShippers: [for (final d in loads.docs) '${d.data()['shipperId'] ?? ''}'],
          bookings: [
            for (final d in bookings.docs)
              (
                customerId: '${d.data()['customerId'] ?? ''}',
                driverId: '${d.data()['driverId'] ?? ''}',
                fleetOwnerId: '${d.data()['fleetOwnerId'] ?? ''}',
                status: '${d.data()['status'] ?? ''}',
              ),
          ],
        );
      });

  /// Today's pilot picture: counts (cheap aggregate reads) plus up to 300 open
  /// loads to find the unfilled ones. About 10 reads per press.
  static Future<PilotControl> pilotControl() => withRetry(() async {
        final now = ServerClock.now();
        final openLoads = await _db.collection('loads').where('status', isEqualTo: LoadStatus.open).limit(PilotControl.sampleLimit).get();
        final r = await Future.wait([
          _count(_db.collection('users').where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(PilotControl.dayStart(now)))),
          _count(_db.collection('driver_presence').where('mode', isEqualTo: 'nearby').where('sharedUntil', isGreaterThan: Timestamp.fromDate(now))),
          _count(_db.collection('bookings').where('status', whereIn: [
            BookingStatus.accepted,
            BookingStatus.driverArriving,
            BookingStatus.loading,
            BookingStatus.pickedUp,
            BookingStatus.inTransit,
            BookingStatus.unloading,
          ])),
          _count(_db.collection('sos_alerts').where('status', isEqualTo: 'open')),
          _count(_db.collection('tickets').where('status', whereIn: ['open', 'in_progress'])),
        ]);
        return PilotControl(
          signupsToday: r[0],
          driversSharing: r[1],
          openLoads: openLoads.docs.length,
          unfilledLoads: PilotControl.unfilled([for (final d in openLoads.docs) (d.data()['createdAt'] as Timestamp?)?.toDate()], now),
          runningTrips: r[2],
          openSos: r[3],
          openTickets: r[4],
        );
      });

  /// Open loads older than the unfilled threshold, oldest first (newest 300 open read).
  static Future<List<Load>> unfilledLoads({DateTime? now}) => withRetry(() async {
        final at = now ?? ServerClock.now();
        final snap = await _db.collection('loads').where('status', isEqualTo: LoadStatus.open).limit(PilotControl.sampleLimit).get();
        final loads = [
          for (final d in snap.docs)
            if (d.data()['createdAt'] is Timestamp && at.difference((d.data()['createdAt'] as Timestamp).toDate()).inMinutes >= PilotControl.unfilledAfterMinutes) Load.fromDoc(d),
        ]..sort((a, b) => a.createdAt!.compareTo(b.createdAt!));
        return loads;
      });

  /// The drivers to suggest for [load] with their names (reads up to 500 free
  /// vehicles and 500 drivers).
  static Future<List<({DispatchCandidate c, String name})>> dispatchCandidates(Load load, {int limit = 500}) => withRetry(() async {
        final vehicles = await _db.collection('vehicles').where('availability', isEqualTo: VehicleAvailability.available).limit(limit).get();
        final users = await _db.collection('users').where('role', isEqualTo: 'driver').limit(limit).get();
        final byId = {for (final u in users.docs) u.id: u.data()};
        final found = Dispatch.suggest(
          load,
          [for (final d in vehicles.docs) Vehicle.fromDoc(d)],
          spotOf: (v) => UserService.lastLocationOf(byId[v.assignedDriverId ?? v.ownerId]),
          now: ServerClock.now(),
        );
        return [for (final c in found) (c: c, name: '${byId[c.driverId]?['driverName'] ?? byId[c.driverId]?['name'] ?? ''}')];
      });

  /// Suggests [load] to a driver: one `dispatch_suggestions` document the
  /// driver sees on their home, plus an audit line. It assigns nothing: the
  /// driver still accepts through the normal flow (record only).
  /// TODO(functions): notify the driver and assign on their consent.
  static Future<void> suggestLoad(Load load, String driverId, {String note = ''}) {
    assert(note.length <= Dispatch.maxNote);
    final batch = _db.batch();
    final id = Dispatch.suggestionId(load.id, driverId);
    batch.set(_db.collection('dispatch_suggestions').doc(id), {
      'loadId': load.id,
      'driverId': driverId,
      'pickup': load.pickup.length > 120 ? load.pickup.substring(0, 120) : load.pickup,
      'drop': load.drop.length > 120 ? load.drop.substring(0, 120) : load.drop,
      'weight': load.weight,
      'vehicleType': load.vehicleType,
      'note': note.trim(),
      'by': Backend.requireUid(),
      'status': 'suggested',
      'createdAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.userAction, targetId: load.id, loadId: load.id, data: {'action': 'dispatch_suggest', 'collection': 'dispatch_suggestions', 'driverId': driverId});
    return batch.commit();
  }

  /// A call-back note about the customer of [load] (kept with the user's admin notes).
  static Future<void> callbackNote(Load load, String text) {
    final t = text.trim();
    assert(t.isNotEmpty && t.length <= 900);
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(load.shipperId).collection('admin_notes').doc(), {
      'by': Backend.requireUid(),
      'text': 'Call-back (load ${load.id}): $t',
      'createdAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.userAction, targetId: load.shipperId, loadId: load.id, data: {'action': 'callback_note', 'collection': 'admin_notes'});
    return batch.commit();
  }

  /// The numbers of today or of the last seven days (see [PilotReport]). About
  /// five aggregate reads plus up to 1,000 bookings.
  static Future<PilotReport> pilotReport({required bool weekly}) => withRetry(() async {
        final now = ServerClock.now();
        final from = PilotReport.periodStart(now, weekly: weekly);
        final since = Timestamp.fromDate(from);
        Query<Map<String, dynamic>> q(String c) => _db.collection(c).where('createdAt', isGreaterThanOrEqualTo: since);
        final bookings = await q('bookings').limit(PilotReport.bookingSample).get();
        final r = await Future.wait([_count(q('users')), _count(q('loads')), _count(q('sos_alerts')), _count(q('tickets'))]);
        return PilotReport(
          weekly: weekly,
          from: from,
          to: DateTime(now.year, now.month, now.day),
          signups: r[0],
          loads: r[1],
          bookings: bookings.docs.length,
          delivered: bookings.docs.where((d) => d.data()['status'] == BookingStatus.delivered).length,
          cancelled: bookings.docs.where((d) => d.data()['status'] == BookingStatus.cancelled).length,
          sos: r[2],
          tickets: r[3],
        );
      });

  /// Weekly load cohorts from the newest 500 loads, 1,000 offers and 1,000
  /// bookings (about 2,500 reads, once per press).
  static Future<List<CohortRow>> pilotCohorts() => withRetry(() async {
        Future<QuerySnapshot<Map<String, dynamic>>> newest(String c, int n) => _db.collection(c).orderBy('createdAt', descending: true).limit(n).get();
        final r = await Future.wait([newest('loads', 500), newest('offers', 1000), newest('bookings', 1000)]);
        DateTime? at(Object? v) => v is Timestamp ? v.toDate() : null;
        return PilotCohorts.compute(
          [for (final d in r[0].docs) if (at(d.data()['createdAt']) != null) CohortLoad(d.id, '${d.data()['shipperId'] ?? ''}', at(d.data()['createdAt'])!)],
          [for (final d in r[1].docs) if (at(d.data()['createdAt']) != null) CohortOffer('${d.data()['loadId'] ?? ''}', at(d.data()['createdAt'])!)],
          [
            for (final d in r[2].docs)
              if (at(d.data()['createdAt']) != null)
                CohortBooking('${d.data()['loadId'] ?? ''}', at(d.data()['createdAt'])!, '${d.data()['status'] ?? ''}', (d.data()['cancellation'] is Map ? (d.data()['cancellation'] as Map)['reason'] : null) as String?),
          ],
        );
      });

  /// "Would you use it again?" answers (newest 500).
  static Future<SurveyStats> surveyStats() => withRetry(() async {
        final snap = await _db.collection('trip_surveys').orderBy('createdAt', descending: true).limit(500).get();
        return SurveyStats.compute([for (final d in snap.docs) d.data()]);
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
