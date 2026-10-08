import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/booking.dart';
import '../models/fleet.dart';
import 'backend.dart';

class FleetException implements Exception {
  /// `phone`, `own_phone`, `already_member`, `no_invite`, `not_driver`.
  final String reason;
  const FleetException(this.reason);

  @override
  String toString() => 'FleetException($reason)';
}

/// Transporter: invite drivers by phone, see members, assign vehicles
/// (VehicleService.assignDriver), watch the fleet's trips. Driver: answer an
/// invite. Records only; earnings are summed from bookings.
class FleetService {
  FleetService._();

  static FirebaseFirestore get _db => Backend.db;

  // ---- owner ----

  static Future<String> invite(String rawPhone) async {
    final uid = Backend.requireUid();
    final phone = FleetInvite.normalisePhone(rawPhone);
    if (phone == null) throw const FleetException('phone');
    final me = (await _db.collection('users').doc(uid).get()).data() ?? const {};
    if (me['phone'] == phone) throw const FleetException('own_phone');
    final id = FleetInvite.idFor(uid, phone);
    final existing = (await _db.collection('fleet_invites').doc(id).get()).data();
    // A declined or cancelled invite can be sent again; pending/accepted cannot.
    if (existing != null && (existing['status'] == FleetInvite.pending || existing['status'] == FleetInvite.accepted)) {
      throw const FleetException('already_member');
    }
    await _db.collection('fleet_invites').doc(id).set({
      'ownerId': uid,
      'ownerName': me['name'] ?? me['companyName'] ?? '',
      'phone': phone,
      'status': FleetInvite.pending,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  static Future<void> cancelInvite(String id) =>
      _db.collection('fleet_invites').doc(id).update({'status': FleetInvite.cancelled, 'answeredAt': FieldValue.serverTimestamp()});

  static Stream<List<FleetInvite>> watchInvitesSent() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('fleet_invites').where('ownerId', isEqualTo: uid).snapshots().map((s) {
      final list = [for (final d in s.docs) FleetInvite.fromDoc(d.id, d.data())];
      list.sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
      return list;
    });
  }

  static Stream<List<FleetMember>> watchMembers() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('fleet_members').where('ownerId', isEqualTo: uid).snapshots().map((s) => [
          for (final d in s.docs) FleetMember.fromDoc(d.id, d.data()),
        ]..sort((a, b) => a.driverName.compareTo(b.driverName)));
  }

  /// The owner removes a driver; vehicles assigned to them go back to the owner.
  static Future<void> removeMember(FleetMember m, {Iterable<String> vehicleIds = const []}) async {
    final batch = _db.batch();
    for (final v in vehicleIds) {
      batch.update(_db.collection('vehicles').doc(v), {'assignedDriverId': FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()});
    }
    batch.update(_db.collection('fleet_members').doc(m.id), {'active': false, 'endedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  /// Bookings run with this owner's vehicles by their drivers, newest first.
  static Stream<List<Booking>> watchFleetBookings() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('bookings').where('fleetOwnerId', isEqualTo: uid).snapshots().map((s) {
      final list = s.docs.map(Booking.fromDoc).toList();
      list.sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 1 << 50).compareTo(a.createdAt?.millisecondsSinceEpoch ?? 1 << 50));
      return list;
    });
  }

  // ---- driver ----

  /// Pending invites addressed to the signed-in user's phone number.
  static Stream<List<FleetInvite>> watchMyInvites() {
    final phone = Backend.currentUser?.phoneNumber;
    if (phone == null || phone.isEmpty) return Stream.value(const []);
    return _db.collection('fleet_invites').where('phone', isEqualTo: phone).snapshots().map((s) => [
          for (final d in s.docs) FleetInvite.fromDoc(d.id, d.data()),
        ].where((i) => i.status == FleetInvite.pending).toList());
  }

  /// Accept (joins the fleet) or decline. Accepting needs the Driver role.
  static Future<void> respond(FleetInvite invite, {required bool accept}) async {
    final uid = Backend.requireUid();
    final phone = Backend.currentUser?.phoneNumber ?? '';
    final me = (await _db.collection('users').doc(uid).get()).data() ?? const {};
    if (accept && me['role'] != 'driver') throw const FleetException('not_driver');
    final batch = _db.batch();
    batch.update(_db.collection('fleet_invites').doc(invite.id), {
      'status': accept ? FleetInvite.accepted : FleetInvite.declined,
      'answeredAt': FieldValue.serverTimestamp(),
    });
    if (accept) {
      batch.set(_db.collection('fleet_members').doc('${invite.ownerId}_$uid'), {
        'ownerId': invite.ownerId,
        'ownerName': invite.ownerName,
        'driverId': uid,
        'driverName': me['driverName'] ?? '',
        'driverPhone': phone,
        'active': true,
        if (_licenceOf(me) != null) 'licenceExpiry': Timestamp.fromDate(_licenceOf(me)!),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static DateTime? _licenceOf(Map<String, dynamic> user) => ((user['driverKyc'] as Map?)?['dlExpiry'] as Timestamp?)?.toDate();

  /// Tells every fleet the driver belongs to when the licence ends, so the
  /// transporter can remind them. Only the date is shared. Quiet on failure
  /// (offline, no licence yet); called when the driver opens the home screen
  /// and after saving documents.
  static Future<void> shareLicenceWithFleets() async {
    try {
      final uid = Backend.uid;
      if (uid == null) return;
      final me = (await _db.collection('users').doc(uid).get()).data() ?? const {};
      final expiry = _licenceOf(me);
      if (expiry == null) return;
      final mine = await _db.collection('fleet_members').where('driverId', isEqualTo: uid).get();
      for (final d in mine.docs) {
        final shared = (d.data()['licenceExpiry'] as Timestamp?)?.toDate();
        if (d.data()['active'] == true && shared != expiry) await d.reference.update({'licenceExpiry': Timestamp.fromDate(expiry)});
      }
    } catch (_) {}
  }

  /// Fleets the signed-in driver belongs to.
  static Stream<List<FleetMember>> watchMyFleets() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('fleet_members').where('driverId', isEqualTo: uid).snapshots().map((s) => [
          for (final d in s.docs) FleetMember.fromDoc(d.id, d.data()),
        ].where((m) => m.active).toList());
  }

  static Future<void> leave(FleetMember m) =>
      _db.collection('fleet_members').doc(m.id).update({'active': false, 'endedAt': FieldValue.serverTimestamp()});
}
