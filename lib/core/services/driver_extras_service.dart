import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/driver_extras.dart';
import 'backend.dart';

class TipException implements Exception {
  final String reason;
  const TipException(this.reason);

  @override
  String toString() => 'TipException($reason)';
}

class ClaimException implements Exception {
  final String reason;
  const ClaimException(this.reason);

  @override
  String toString() => 'ClaimException($reason)';
}

/// Tips, driver incentives and driver plans. All records: no money moves.
/// TODO(functions): count trips and approve claims server-side; LATER(paid):
/// pay bonuses and charge for Pro.
class DriverExtrasService {
  DriverExtrasService._();

  static FirebaseFirestore get _db => Backend.db;

  // ------------------------------------------------------------------
  // tips
  // ------------------------------------------------------------------

  /// Customer: record a tip for a delivered booking (once).
  static Future<void> addTip(Booking b, int amountPaise) async {
    final uid = Backend.requireUid();
    if (amountPaise < 100 || amountPaise > Tip.maxPaise) throw const TipException('amount');
    if (b.customerId != uid) throw const TipException('not_yours');
    if (b.status != BookingStatus.delivered) throw const TipException('not_delivered');
    final ref = _db.collection('tips').doc(b.id);
    if ((await ref.get()).exists) throw const TipException('already');
    await ref.set({
      'bookingId': b.id,
      'customerId': uid,
      'driverId': b.driverId,
      'amountPaise': amountPaise,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<Tip?> watchTipFor(String bookingId) =>
      _db.collection('tips').doc(bookingId).snapshots().map((s) => s.exists ? Tip.fromDoc(s.id, s.data()!) : null);

  /// The signed-in driver's tips, newest first.
  static Stream<List<Tip>> watchMyTips() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('tips').where('driverId', isEqualTo: uid).snapshots().map((s) {
      final list = [for (final d in s.docs) Tip.fromDoc(d.id, d.data())];
      list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  /// Tips the signed-in customer gave, newest first.
  static Stream<List<Tip>> watchGivenTips() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('tips').where('customerId', isEqualTo: uid).snapshots().map((s) {
      final list = [for (final d in s.docs) Tip.fromDoc(d.id, d.data())];
      list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  // ------------------------------------------------------------------
  // incentives
  // ------------------------------------------------------------------

  static Stream<List<Incentive>> watchIncentives({bool onlyActive = true}) {
    Query<Map<String, dynamic>> q = _db.collection('incentives');
    if (onlyActive) q = q.where('active', isEqualTo: true);
    return q.snapshots().map((s) {
      final list = [for (final d in s.docs) Incentive.fromDoc(d.id, d.data())];
      list.sort((a, b) => b.startsAt.compareTo(a.startsAt));
      return list;
    });
  }

  /// Admin: create (no [id]) or update an incentive.
  static Future<void> saveIncentive(Incentive i, {String? id}) async {
    final ref = id == null ? _db.collection('incentives').doc() : _db.collection('incentives').doc(id);
    await ref.set({
      ...i.toMap(),
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<List<IncentiveClaim>> watchMyClaims() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('incentive_claims').where('driverId', isEqualTo: uid).snapshots().map(_claims);
  }

  /// Admin: every claim, newest first.
  static Stream<List<IncentiveClaim>> watchAllClaims() => _db.collection('incentive_claims').limit(300).snapshots().map(_claims);

  static List<IncentiveClaim> _claims(QuerySnapshot<Map<String, dynamic>> s) {
    final list = [for (final d in s.docs) IncentiveClaim.fromDoc(d.id, d.data())];
    list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return list;
  }

  /// Driver: claim the bonus once the target is reached. [bookings] are the
  /// driver's own bookings (trips are counted on the device).
  static Future<void> claim(Incentive i, Iterable<Booking> bookings, {DateTime? now}) async {
    final uid = Backend.requireUid();
    if (!i.canClaim(bookings, now ?? DateTime.now())) throw const ClaimException('not_reached');
    final ref = _db.collection('incentive_claims').doc('${i.id}_$uid');
    if ((await ref.get()).exists) throw const ClaimException('already');
    await ref.set({
      'incentiveId': i.id,
      'driverId': uid,
      'bonusPaise': i.bonusPaise,
      'status': IncentiveClaim.claimed,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin: mark a claim paid (after paying it outside the app).
  static Future<void> markClaimPaid(String claimId) => _db.collection('incentive_claims').doc(claimId).update({
        'status': IncentiveClaim.paid,
        'paidAt': FieldValue.serverTimestamp(),
      });

  // ------------------------------------------------------------------
  // plans
  // ------------------------------------------------------------------

  /// Driver: ask for Pro. One request document per driver.
  static Future<void> requestPro() async {
    final uid = Backend.requireUid();
    final ref = _db.collection('plan_requests').doc(uid);
    final existing = (await ref.get()).data();
    if (existing?['status'] == DriverPlan.requestPending) throw const ClaimException('already');
    await ref.set({
      'uid': uid,
      'plan': DriverPlan.pro,
      'status': DriverPlan.requestPending,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<Map<String, dynamic>?> watchMyPlanRequest() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(null);
    return _db.collection('plan_requests').doc(uid).snapshots().map((s) => s.data());
  }

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchPlanRequests() =>
      _db.collection('plan_requests').limit(300).snapshots().map((s) => s.docs);

  /// Admin: set a driver's plan (and answer their request, if any).
  /// [days] null = no end date. Rules let only admins write these fields.
  static Future<void> setPlan(String driverId, String plan, {int? days}) async {
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(driverId), {
      'plan': plan,
      'planUntil': days == null || plan == DriverPlan.free ? FieldValue.delete() : Timestamp.fromDate(DateTime.now().add(Duration(days: days))),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final req = _db.collection('plan_requests').doc(driverId);
    if ((await req.get()).exists) {
      batch.update(req, {
        'status': plan == DriverPlan.pro ? DriverPlan.requestApproved : DriverPlan.requestRejected,
        'answeredAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Admin: turn down a request without changing the plan.
  static Future<void> rejectPlanRequest(String driverId) => _db.collection('plan_requests').doc(driverId).update({
        'status': DriverPlan.requestRejected,
        'answeredAt': FieldValue.serverTimestamp(),
      });
}
