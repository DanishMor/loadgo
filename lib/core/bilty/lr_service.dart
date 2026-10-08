import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../enterprise/validators.dart';
import '../models/app_notification.dart';
import '../models/booking.dart';
import '../services/audit_service.dart';
import '../services/backend.dart';
import '../services/server_clock.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import 'lr_model.dart';
import 'lr_visibility.dart';

class LrException implements Exception {
  /// 'not_allowed', 'fields', 'advance', 'gstin', 'eway', 'cancelled_booking', 'reason', 'not_current', 'no_driver'.
  final String reason;
  LrException(this.reason);
  @override
  String toString() => 'LrException($reason)';
}

/// What the issuer types in. Money is integer paise.
class LrDraft {
  final String consignorName;
  final String consigneeName;
  final String goods;
  final int packages;
  final num weightTons;
  final int freightPaise;
  final int advancePaise;
  final int marginPaise;
  final int gstPaise;
  final String consignorPhone;
  final String consigneePhone;
  final int goodsValuePaise;
  final String invoiceNo;
  final String consignorGstin;
  final String consigneeGstin;
  final String ewayBillNo;
  final DateTime? ewayValidUntil;
  final String complianceMode;

  const LrDraft({
    required this.consignorName,
    required this.consigneeName,
    required this.goods,
    this.packages = 0,
    this.weightTons = 0,
    this.freightPaise = 0,
    this.advancePaise = 0,
    this.marginPaise = 0,
    this.gstPaise = 0,
    this.consignorPhone = '',
    this.consigneePhone = '',
    this.goodsValuePaise = 0,
    this.invoiceNo = '',
    this.consignorGstin = '',
    this.consigneeGstin = '',
    this.ewayBillNo = '',
    this.ewayValidUntil,
    this.complianceMode = ComplianceMode.hide,
  });

  int get balancePaise => freightPaise - advancePaise;

  /// Throws [LrException] with the first thing wrong.
  void validate() {
    if (consignorName.trim().isEmpty || consigneeName.trim().isEmpty || goods.trim().isEmpty) throw LrException('fields');
    if (freightPaise < 0 || advancePaise < 0 || advancePaise > freightPaise) throw LrException('advance');
    for (final g in [consignorGstin, consigneeGstin]) {
      if (g.trim().isNotEmpty && !isValidGstinFormat(g)) throw LrException('gstin');
    }
    if (ewayBillNo.trim().isNotEmpty && !RegExp(r'^\d{12}$').hasMatch(ewayBillNo.trim())) throw LrException('eway');
  }

  LrDetails details() => LrDetails(
        freightPaise: freightPaise,
        advancePaise: advancePaise,
        balancePaise: balancePaise,
        marginPaise: marginPaise,
        gstPaise: gstPaise,
        consignorPhone: consignorPhone.trim(),
        consigneePhone: consigneePhone.trim(),
      );

  LrCompliance compliance() => LrCompliance(
        goodsValuePaise: goodsValuePaise,
        invoiceNo: invoiceNo.trim(),
        consignorGstin: consignorGstin.trim().toUpperCase(),
        consigneeGstin: consigneeGstin.trim().toUpperCase(),
        ewayBillNo: ewayBillNo.trim(),
        ewayValidUntil: ewayValidUntil,
      );

  /// A starting point from the booking (and the issuer's role).
  factory LrDraft.fromBooking(Booking b, {required String issuerRole}) => LrDraft(
        consignorName: '',
        consigneeName: b.deliveryProof?.receiverName ?? '',
        goods: b.cargoType,
        packages: b.pickupProof?.packages ?? 0,
        weightTons: b.pickupProof?.weightTons ?? b.weight,
        freightPaise: issuerRole == LrIssuerRole.customer ? (b.agreedFarePaise ?? 0) : 0,
        ewayBillNo: b.ewayBillNo,
        ewayValidUntil: b.ewayValidUntil,
      );
}

/// A link to one copy of an LR (`lr_shares/{token}`).
class LrShare {
  final String token;
  final String lrId;
  final String copyType;
  final DateTime? expiresAt;
  final bool revoked;
  final int views;
  const LrShare({required this.token, required this.lrId, required this.copyType, this.expiresAt, this.revoked = false, this.views = 0});

  bool isLive(DateTime now) => !revoked && (expiresAt == null || expiresAt!.isAfter(now));

  factory LrShare.fromDoc(String id, Map<String, dynamic> d) => LrShare(
        token: id,
        lrId: d['lrId'] as String? ?? '',
        copyType: d['copyType'] as String? ?? LrCopy.full,
        expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
        revoked: d['revoked'] == true,
        views: (d['views'] as num?)?.toInt() ?? 0,
      );
}

/// Bilty (LR) records: issue, new version, cancel, compliance mode, share links.
/// LATER(paid): e-way bill generation through a GSP API.
class LrService {
  LrService._();

  static FirebaseFirestore get _db => Backend.db;
  static CollectionReference<Map<String, dynamic>> get _lrs => _db.collection('lrs');
  static CollectionReference<Map<String, dynamic>> get _shares => _db.collection('lr_shares');

  /// Where verify and share links open (hosting/lr.html).
  static String host = 'loadgo-defc2.web.app';
  static String linkFor(String token) => 'https://$host/lr/$token';

  static const shareDefaultAfterDelivery = Duration(days: 2);

  /// Default end of a share link: delivery + 2 days; before delivery the pickup
  /// date (or now) + 3 days of transit + 2 days.
  static DateTime defaultExpiry(Booking b, DateTime now) {
    final delivered = b.timeline[BookingStatus.delivered];
    if (delivered != null) return delivered.add(shareDefaultAfterDelivery);
    final start = (b.pickupDate != null && b.pickupDate!.isAfter(now)) ? b.pickupDate! : now;
    return start.add(const Duration(days: 3)).add(shareDefaultAfterDelivery);
  }

  // ---- reading ----

  /// Every version of the LRs of a booking (the rules let the parties and the
  /// trip driver list by booking).
  static Stream<List<LrPublic>> watchForBooking(String bookingId) => _lrs.where('bookingId', isEqualTo: bookingId).snapshots().map((s) {
        final list = [for (final d in s.docs) LrPublic.fromDoc(d.id, d.data())];
        list.sort((a, b) => a.seq != b.seq ? b.seq.compareTo(a.seq) : b.version.compareTo(a.version));
        return list;
      });

  /// The version to work with: the issued one, else the newest.
  static LrPublic? current(List<LrPublic> all) {
    for (final l in all) {
      if (l.isCurrent) return l;
    }
    return all.isEmpty ? null : all.first;
  }

  /// Reads the private parts the viewer may read (the driver reads none).
  static Future<LrBundle> bundle(LrPublic pub) async {
    Future<Map<String, dynamic>?> read(String name) async {
      try {
        final s = await _lrs.doc(pub.id).collection('private').doc(name).get();
        return s.data();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') return null;
        rethrow;
      }
    }

    final fresh = await _lrs.doc(pub.id).get();
    final latest = fresh.exists ? LrPublic.fromDoc(fresh.id, fresh.data()!) : pub;
    final d = await read('details');
    final c = await read('compliance');
    return LrBundle(latest, details: d == null ? null : LrDetails.fromMap(d), compliance: c == null ? null : LrCompliance.fromMap(c));
  }

  // ---- writing ----

  static Future<String> _issuerName(String role) async {
    final u = await UserService.getUser();
    final company = (u?['companyName'] as String?)?.trim() ?? '';
    final name = (u?['name'] as String?)?.trim() ?? '';
    return (role == LrIssuerRole.transporter && company.isNotEmpty ? company : name);
  }

  static String roleFor(Booking b, String uid) {
    if (b.customerId == uid) return LrIssuerRole.customer;
    if (b.fleetOwnerId == uid) return LrIssuerRole.transporter;
    throw LrException('not_allowed');
  }

  /// Only the transporter and the customer of the booking, never a driver.
  static bool canIssue(Booking b, String uid) => LrVisibility.canIssue(
        isCustomerOfBooking: b.customerId == uid,
        isTransporterOfBooking: b.fleetOwnerId == uid,
        isDriver: b.customerId != uid && b.fleetOwnerId != uid,
        isAdmin: false,
      );

  static Map<String, Object?> _publicMap(Booking b, String uid, String role, String issuerName, LrDraft d, int year, int seq, int version) {
    final driverName = b.assignedDriverName.isNotEmpty ? b.assignedDriverName : b.driverName;
    final vehicle = b.assignedVehicleNumber.isNotEmpty ? b.assignedVehicleNumber : b.vehicleNumber;
    return {
      'bookingId': b.id,
      'issuerId': uid,
      'issuerRole': role,
      'customerId': b.customerId,
      'fleetOwnerId': ?b.fleetOwnerId,
      'lrNo': lrNumber(role, year, seq),
      'seq': seq,
      'year': year,
      'version': version,
      'status': LrStatus.issued,
      'date': Timestamp.now(),
      'pickup': b.pickup,
      'drop': b.drop,
      'route': b.route.join(' → '),
      'goods': d.goods.trim(),
      'packages': d.packages,
      'weightTons': d.weightTons,
      'vehicleNumber': vehicle,
      'driverName': driverName,
      'consignorName': d.consignorName.trim(),
      'consigneeName': d.consigneeName.trim(),
      'issuerName': issuerName,
      'complianceMode': d.complianceMode,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Issues the first version. The number comes from `lr_series/{issuer}_{year}`,
  /// bumped in the same transaction, so it is unique per issuer.
  static Future<LrPublic> issue(Booking b, LrDraft d) async {
    final uid = Backend.requireUid();
    if (!canIssue(b, uid)) throw LrException('not_allowed');
    if (b.status == BookingStatus.cancelled) throw LrException('cancelled_booking');
    d.validate();
    final role = roleFor(b, uid);
    final name = await _issuerName(role);
    final year = DateTime.now().year;
    final series = _db.collection('lr_series').doc('${uid}_$year');
    late LrPublic made;
    await _db.runTransaction((tx) async {
      final counter = await tx.get(series);
      final seq = counter.exists ? (counter.data()!['next'] as num).toInt() : 1;
      final id = lrDocId(uid, year, seq, 1);
      final ref = _lrs.doc(id);
      tx.set(series, {'next': seq + 1, 'updatedAt': FieldValue.serverTimestamp()});
      tx.set(ref, _publicMap(b, uid, role, name, d, year, seq, 1));
      tx.set(ref.collection('private').doc('details'), {...d.details().toMap(), 'createdAt': FieldValue.serverTimestamp()});
      tx.set(ref.collection('private').doc('compliance'), {...d.compliance().toMap(), 'createdAt': FieldValue.serverTimestamp()});
      AuditService.inTransaction(tx, AuditType.lrIssue, bookingId: b.id, data: {'lrId': id, 'lrNo': lrNumber(role, year, seq), 'role': role});
      made = LrPublic(id: id, bookingId: b.id, issuerId: uid, issuerRole: role, customerId: b.customerId, lrNo: lrNumber(role, year, seq), seq: seq, year: year, version: 1, status: LrStatus.issued);
    });
    return _reload(made);
  }

  static Future<LrPublic> _reload(LrPublic p) async {
    final s = await _lrs.doc(p.id).get();
    return s.exists ? LrPublic.fromDoc(s.id, s.data()!) : p;
  }

  /// The server's word on the status: a copy held in memory may be stale.
  static Future<void> _mustBeCurrent(LrPublic lr) async {
    final s = await _lrs.doc(lr.id).get();
    if (!s.exists || s.data()!['status'] != LrStatus.issued) throw LrException('not_current');
  }

  /// Edit after issue = a new version with the same number; the old version
  /// becomes `superseded` and stays view-only.
  static Future<LrPublic> newVersion(Booking b, LrPublic old, LrDraft d) async {
    final uid = Backend.requireUid();
    if (old.issuerId != uid || !canIssue(b, uid)) throw LrException('not_allowed');
    await _mustBeCurrent(old);
    d.validate();
    final name = await _issuerName(old.issuerRole);
    final version = old.version + 1;
    final id = lrDocId(uid, old.year, old.seq, version);
    final batch = _db.batch();
    batch.update(_lrs.doc(old.id), {'status': LrStatus.superseded, 'supersededBy': version, 'updatedAt': FieldValue.serverTimestamp()});
    final ref = _lrs.doc(id);
    batch.set(ref, _publicMap(b, uid, old.issuerRole, name, d, old.year, old.seq, version));
    batch.set(ref.collection('private').doc('details'), {...d.details().toMap(), 'createdAt': FieldValue.serverTimestamp()});
    batch.set(ref.collection('private').doc('compliance'), {...d.compliance().toMap(), 'createdAt': FieldValue.serverTimestamp()});
    AuditService.inBatch(batch, AuditType.lrVersion, bookingId: b.id, data: {'lrId': id, 'lrNo': old.lrNo, 'version': version, 'previous': old.id});
    await batch.commit();
    await _syncVerifyShares(old.id, LrStatus.superseded);
    return _reload(LrPublic(id: id, bookingId: b.id, issuerId: uid, issuerRole: old.issuerRole, customerId: b.customerId, lrNo: old.lrNo, seq: old.seq, year: old.year, version: version, status: LrStatus.issued));
  }

  static Future<void> cancel(LrPublic lr, String reason) async {
    final uid = Backend.requireUid();
    final r = reason.trim();
    if (lr.issuerId != uid) throw LrException('not_allowed');
    await _mustBeCurrent(lr);
    if (r.length < 3 || r.length > 200) throw LrException('reason');
    final batch = _db.batch();
    batch.update(_lrs.doc(lr.id), {'status': LrStatus.cancelled, 'cancelReason': r, 'updatedAt': FieldValue.serverTimestamp()});
    AuditService.inBatch(batch, AuditType.lrCancel, bookingId: lr.bookingId, data: {'lrId': lr.id, 'lrNo': lr.lrNo, 'reason': r});
    await batch.commit();
    await _syncVerifyShares(lr.id, LrStatus.cancelled);
  }

  /// Change of the compliance mode: no new version, but written to the audit log.
  static Future<void> setComplianceMode(LrPublic lr, String mode) async {
    final uid = Backend.requireUid();
    if (lr.issuerId != uid) throw LrException('not_allowed');
    if (!ComplianceMode.all.contains(mode)) throw LrException('fields');
    if (mode == lr.complianceMode) return;
    final batch = _db.batch();
    batch.update(_lrs.doc(lr.id), {'complianceMode': mode, 'updatedAt': FieldValue.serverTimestamp()});
    AuditService.inBatch(batch, AuditType.lrMode, bookingId: lr.bookingId, data: {'lrId': lr.id, 'from': lr.complianceMode, 'to': mode});
    await batch.commit();
  }

  /// In-app delivery to the driver of the trip: a notice; the driver then reads
  /// the driver copy on the trip screen.
  static Future<void> sendToDriver(Booking b, LrPublic lr) async {
    final uid = Backend.requireUid();
    if (lr.issuerId != uid) throw LrException('not_allowed');
    final driver = b.assignedDriverId ?? (b.fleetOwnerId == null ? b.driverId : null);
    if (driver == null || driver == uid) throw LrException('no_driver');
    final batch = _db.batch();
    NotificationService.addInBatch(batch, userId: driver, type: NotificationType.lrSent, message: '${lr.lrNo}: ${b.pickup} → ${b.drop}', relatedId: b.id);
    AuditService.inBatch(batch, AuditType.lrShare, bookingId: b.id, targetId: driver, data: {'lrId': lr.id, 'channel': 'in_app', 'copy': LrCopy.driver});
    await batch.commit();
  }

  /// Audit line for a PDF handed to the share sheet.
  static Future<void> noteShare(Booking b, LrPublic lr, String copy, String channel) =>
      AuditService.record(AuditType.lrShare, bookingId: b.id, data: {'lrId': lr.id, 'channel': channel, 'copy': copy});

  // ---- share links ----

  /// 128 random bits as 32 hex letters.
  static String newToken([Random? rng]) {
    final r = rng ?? Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static Stream<List<LrShare>> watchShares(String lrId) {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _shares.where('ownerId', isEqualTo: uid).where('lrId', isEqualTo: lrId).snapshots().map((s) => [for (final d in s.docs) LrShare.fromDoc(d.id, d.data())]
      ..sort((a, b) => (b.expiresAt ?? DateTime(0)).compareTo(a.expiresAt ?? DateTime(0))));
  }

  /// Creates a link holding a snapshot of exactly [fields] (build them with
  /// [LrVisibility.snapshot]). Returns the token.
  static Future<String> createShare(
    Booking b,
    LrPublic lr,
    String copy,
    Map<String, Object> fields, {
    DateTime? expiresAt,
    DateTime? now,
  }) async {
    final uid = Backend.requireUid();
    if (lr.issuerId != uid) throw LrException('not_allowed');
    final clock = now ?? ServerClock.now();
    final end = expiresAt ?? defaultExpiry(b, clock);
    final token = newToken();
    final batch = _db.batch();
    batch.set(_shares.doc(token), {
      'lrId': lr.id,
      'bookingId': lr.bookingId,
      'ownerId': uid,
      'copyType': copy,
      'fields': fields,
      'status': lr.status,
      'statusAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(end),
      'createdAt': FieldValue.serverTimestamp(),
      'revoked': false,
      'views': 0,
    });
    if (copy != 'verify') AuditService.inBatch(batch, AuditType.lrShare, bookingId: lr.bookingId, data: {'lrId': lr.id, 'channel': 'link', 'copy': copy});
    await batch.commit();
    return token;
  }

  /// The link behind the QR code of the PDF: shows only LR no, route, status
  /// and issuer. One per LR version; reused while it is still valid.
  static Future<String> verifyToken(Booking b, LrPublic lr) async {
    final uid = Backend.requireUid();
    final now = ServerClock.now();
    final mine = await _shares.where('ownerId', isEqualTo: uid).where('lrId', isEqualTo: lr.id).get();
    for (final d in mine.docs) {
      final s = LrShare.fromDoc(d.id, d.data());
      if (s.copyType == 'verify' && s.isLive(now.add(const Duration(days: 2)))) return d.id;
    }
    return createShare(b, lr, 'verify', LrVisibility.verifySnapshot(lr), expiresAt: now.add(const Duration(days: 180)), now: now);
  }

  static Future<void> revokeShare(LrShare s, LrPublic lr) async {
    final batch = _db.batch();
    batch.update(_shares.doc(s.token), {'revoked': true, 'status': lr.status, 'statusAt': FieldValue.serverTimestamp()});
    AuditService.inBatch(batch, AuditType.lrRevoke, bookingId: lr.bookingId, data: {'lrId': lr.id, 'copy': s.copyType});
    await batch.commit();
  }

  /// Keeps the status on the verify links current after a new version or cancel.
  static Future<void> _syncVerifyShares(String lrId, String status) async {
    final uid = Backend.uid;
    if (uid == null) return;
    try {
      final mine = await _shares.where('ownerId', isEqualTo: uid).where('lrId', isEqualTo: lrId).get();
      final batch = _db.batch();
      for (final d in mine.docs) {
        if (d.data()['revoked'] == true) continue;
        batch.update(d.reference, {'status': status, 'statusAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
    } on FirebaseException {
      // The links keep their old status; the LR itself is already saved.
    }
  }
}
