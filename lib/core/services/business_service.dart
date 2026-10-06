import 'package:cloud_firestore/cloud_firestore.dart';

import '../enterprise/business_roles.dart';
import '../models/booking.dart';
import '../models/business.dart';
import '../models/fleet.dart';
import 'backend.dart';

class BusinessTeamException implements Exception {
  /// `phone`, `own_phone`, `already_member`, `not_customer`, `no_company`.
  final String reason;
  const BusinessTeamException(this.reason);

  @override
  String toString() => 'BusinessTeamException($reason)';
}

/// Company account on top of a customer account: team members (bookers) join
/// by phone invite, loads carry the company id and a cost centre, and the
/// owner saves a monthly statement record. Records only; nothing is billed.
class BusinessService {
  BusinessService._();

  static FirebaseFirestore get _db => Backend.db;

  // ---- owner ----

  static Future<String> invite(String rawPhone, {String role = BizRole.booker}) async {
    if (!BizRole.assignable.contains(role)) throw ArgumentError.value(role, 'role');
    final uid = Backend.requireUid();
    final phone = FleetInvite.normalisePhone(rawPhone);
    if (phone == null) throw const BusinessTeamException('phone');
    final me = (await _db.collection('users').doc(uid).get()).data() ?? const {};
    final company = ((me['business'] as Map?)?['legalName'] as String?) ?? '';
    if (company.trim().isEmpty) throw const BusinessTeamException('no_company');
    if (me['phone'] == phone) throw const BusinessTeamException('own_phone');
    final id = FleetInvite.idFor(uid, phone);
    final old = (await _db.collection('business_invites').doc(id).get()).data();
    if (old != null && (old['status'] == BusinessInvite.pending || old['status'] == BusinessInvite.accepted)) {
      throw const BusinessTeamException('already_member');
    }
    await _db.collection('business_invites').doc(id).set({
      'ownerId': uid,
      'ownerName': company.trim(),
      'phone': phone,
      'status': BusinessInvite.pending,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  static Future<void> cancelInvite(String id) =>
      _db.collection('business_invites').doc(id).update({'status': BusinessInvite.cancelled, 'answeredAt': FieldValue.serverTimestamp()});

  static Stream<List<BusinessInvite>> watchInvitesSent() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('business_invites').where('ownerId', isEqualTo: uid).snapshots().map((s) => [
          for (final d in s.docs) BusinessInvite.fromDoc(d.id, d.data()),
        ]..sort((a, b) => a.phone.compareTo(b.phone)));
  }

  static Stream<List<BusinessMember>> watchMembers() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('business_members').where('ownerId', isEqualTo: uid).snapshots().map((s) => [
          for (final d in s.docs) BusinessMember.fromDoc(d.id, d.data()),
        ].where((m) => m.active).toList()
          ..sort((a, b) => a.memberName.compareTo(b.memberName)));
  }

  /// The owner changes a member's role (A4, BIZ4).
  static Future<void> setRole(BusinessMember m, String role) {
    if (!BizRole.assignable.contains(role)) throw ArgumentError.value(role, 'role');
    return _db.collection('business_members').doc(m.id).update({'role': role});
  }

  static Future<void> removeMember(BusinessMember m) =>
      _db.collection('business_members').doc(m.id).update({'active': false, 'endedAt': FieldValue.serverTimestamp()});

  // ---- member ----

  static Stream<List<BusinessInvite>> watchMyInvites() {
    final phone = Backend.currentUser?.phoneNumber;
    if (phone == null || phone.isEmpty) return Stream.value(const []);
    return _db.collection('business_invites').where('phone', isEqualTo: phone).snapshots().map((s) => [
          for (final d in s.docs) BusinessInvite.fromDoc(d.id, d.data()),
        ].where((i) => i.status == BusinessInvite.pending).toList());
  }

  static Future<void> respond(BusinessInvite invite, {required bool accept}) async {
    final uid = Backend.requireUid();
    final me = (await _db.collection('users').doc(uid).get()).data() ?? const {};
    if (accept && me['role'] != 'customer') throw const BusinessTeamException('not_customer');
    final batch = _db.batch();
    batch.update(_db.collection('business_invites').doc(invite.id), {
      'status': accept ? BusinessInvite.accepted : BusinessInvite.declined,
      'answeredAt': FieldValue.serverTimestamp(),
    });
    if (accept) {
      batch.set(_db.collection('business_members').doc('${invite.ownerId}_$uid'), {
        'ownerId': invite.ownerId,
        'ownerName': invite.ownerName,
        'memberId': uid,
        'memberName': me['name'] ?? '',
        'memberPhone': Backend.currentUser?.phoneNumber ?? '',
        'role': invite.role,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static Stream<List<BusinessMember>> watchMyMemberships() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('business_members').where('memberId', isEqualTo: uid).snapshots().map((s) => [
          for (final d in s.docs) BusinessMember.fromDoc(d.id, d.data()),
        ].where((m) => m.active).toList());
  }

  static Future<void> leave(BusinessMember m) => removeMember(m);

  /// The company the signed-in user acts for and their role there: a team
  /// membership first, else their own company profile (owner), else null.
  static Future<BizContext?> myContext() async {
    final uid = Backend.uid;
    if (uid == null) return null;
    final mine = await _db.collection('business_members').where('memberId', isEqualTo: uid).get();
    for (final d in mine.docs) {
      if (d.data()['active'] == true) return BizContext(d.data()['ownerId'] as String, d.data()['role'] as String? ?? BizRole.booker);
    }
    final me = (await _db.collection('users').doc(uid).get()).data() ?? const {};
    final name = ((me['business'] as Map?)?['legalName'] as String?) ?? '';
    return name.trim().isEmpty ? null : BizContext(uid, BizRole.owner);
  }

  /// The company a new load should be booked under: the one the signed-in
  /// user may post for (a booker, manager or dispatch role, or the owner),
  /// else null.
  static Future<String?> postingBusinessId() async {
    final c = await myContext();
    return c != null && c.can(BizPerm.postLoads) ? c.ownerId : null;
  }

  // ---- statement ----

  /// Delivered bookings carrying this owner's company id.
  static Stream<List<Booking>> watchCompanyBookings({String? ownerId}) {
    final uid = ownerId ?? Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('bookings').where('businessId', isEqualTo: uid).snapshots().map((s) => s.docs.map(Booking.fromDoc).toList());
  }

  /// Saves (or replaces) the owner's record of [statement].
  static Future<void> saveStatement(MonthlyStatement s, {String? ownerId}) {
    final uid = ownerId ?? Backend.requireUid();
    return _db.collection('business_statements').doc('${uid}_${s.month}').set({
      'ownerId': uid,
      'month': s.month,
      'trips': s.trips,
      'totalPaise': s.totalPaise,
      'byCostCenter': {for (final e in s.byCostCenter.entries) e.key.isEmpty ? '-' : e.key: e.value},
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<Map<String, dynamic>>> watchSavedStatements({String? ownerId}) {
    final uid = ownerId ?? Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('business_statements').where('ownerId', isEqualTo: uid).snapshots().map((s) => [
          for (final d in s.docs) d.data(),
        ]..sort((a, b) => (b['month'] as String).compareTo(a['month'] as String)));
  }
}
