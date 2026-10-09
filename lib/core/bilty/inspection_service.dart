import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../models/app_notification.dart';
import '../models/booking.dart';
import '../services/audit_service.dart';
import '../services/backend.dart';
import '../services/server_clock.dart';
import '../services/notification_service.dart';
import 'lr_copy_view.dart';
import 'lr_model.dart';
import 'lr_pdf.dart';
import 'lr_service.dart';
import 'lr_visibility.dart';

/// `lrs/{id}/inspection_grants/{driverId}`: until [expiresAt] the trip driver
/// may read the compliance group (the rules stop honouring it at that time).
class InspectionGrant {
  final String driverId;
  final String kind;
  final DateTime expiresAt;
  final String verifyToken;
  const InspectionGrant({required this.driverId, required this.kind, required this.expiresAt, this.verifyToken = ''});

  bool isValid(DateTime now) => expiresAt.isAfter(now);

  factory InspectionGrant.fromDoc(String id, Map<String, dynamic> d) => InspectionGrant(
        driverId: id,
        kind: d['kind'] as String? ?? 'approved',
        expiresAt: (d['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
        verifyToken: d['verifyToken'] as String? ?? '',
      );
}

/// One line of the inspection history of an LR (`lrs/{id}/inspection_log`).
class InspectionLogEntry {
  final String id;

  /// requested, approved, denied, allowed (in advance) or revoked.
  final String kind;
  final String driverId;
  final int? hours;
  final DateTime? at;
  const InspectionLogEntry({required this.id, required this.kind, required this.driverId, this.hours, this.at});

  factory InspectionLogEntry.fromMap(String id, Map<String, dynamic> d) => InspectionLogEntry(
        id: id,
        kind: d['kind'] as String? ?? '',
        driverId: d['driverId'] as String? ?? '',
        hours: (d['hours'] as num?)?.toInt(),
        at: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// `lrs/{id}/inspection_requests/{driverId}`.
class InspectionRequest {
  final String driverId;
  final String driverName;
  final String status;
  final DateTime? requestedAt;
  const InspectionRequest({required this.driverId, this.driverName = '', required this.status, this.requestedAt});

  bool get pending => status == 'pending';

  factory InspectionRequest.fromDoc(String id, Map<String, dynamic> d) => InspectionRequest(
        driverId: id,
        driverName: d['driverName'] as String? ?? '',
        status: d['status'] as String? ?? 'pending',
        requestedAt: (d['requestedAt'] as Timestamp?)?.toDate(),
      );
}

class InspectionException implements Exception {
  /// 'not_allowed', 'no_driver', 'not_current', 'hours'.
  final String reason;
  InspectionException(this.reason);
  @override
  String toString() => 'InspectionException($reason)';
}

/// Inspection mode (Task 71): the driver asks to show the compliance group at
/// an RTO or GST check, the owner approves for 2 hours (or allows it in
/// advance), the rules refuse the read once the grant has run out, and an
/// offline "Inspection copy" PDF is kept on the driver's phone only while the
/// grant lasts. Every request, approval, denial and expiry is in `audit_events`.
class InspectionService {
  InspectionService._();

  static FirebaseFirestore get _db => Backend.db;

  /// Injectable clock for tests.
  static DateTime Function() now = ServerClock.now;

  static const approvalDuration = Duration(hours: 2);

  /// The rules accept a grant that ends at most 2 hours (or N hours, for an
  /// advance one) after the SERVER time of the write. A phone clock even a few
  /// seconds ahead would make the roadside approval fail, so the grant is
  /// written this much shorter (MASTER-5 Task 20).
  static const clockMargin = Duration(seconds: 30);
  static const maxAdvance = Duration(hours: 72);

  /// How long a copy saved because of mode `show` stays on the phone.
  static const showModeCacheTtl = Duration(hours: 12);

  static DocumentReference<Map<String, dynamic>> _grant(String lrId, String driverId) => _db.collection('lrs').doc(lrId).collection('inspection_grants').doc(driverId);
  static DocumentReference<Map<String, dynamic>> _req(String lrId, String driverId) => _db.collection('lrs').doc(lrId).collection('inspection_requests').doc(driverId);

  /// The driver who is on the road for [b].
  static String? tripDriver(Booking b) => b.assignedDriverId ?? (b.fleetOwnerId == null ? b.driverId : null);

  // ---- watching ----

  static Stream<InspectionGrant?> watchGrant(String lrId, String driverId) =>
      _grant(lrId, driverId).snapshots().map((s) => s.exists ? InspectionGrant.fromDoc(s.id, s.data()!) : null);

  static Stream<InspectionRequest?> watchRequest(String lrId, String driverId) =>
      _req(lrId, driverId).snapshots().map((s) => s.exists ? InspectionRequest.fromDoc(s.id, s.data()!) : null);

  static CollectionReference<Map<String, dynamic>> _log(String lrId) => _db.collection('lrs').doc(lrId).collection('inspection_log');

  static void _logEntry(WriteBatch batch, String lrId, String kind, String driverId, {int? hours}) =>
      batch.set(_log(lrId).doc(), {'kind': kind, 'driverId': driverId, 'by': Backend.requireUid(), 'hours': ?hours, 'createdAt': FieldValue.serverTimestamp()});

  /// The last [limit] events of this LR's inspection mode (newest first).
  static Stream<List<InspectionLogEntry>> watchLog(String lrId, {int limit = 15}) => _log(lrId).orderBy('createdAt', descending: true).limit(limit).snapshots().map((s) => [for (final d in s.docs) InspectionLogEntry.fromMap(d.id, d.data())]);

  static Stream<List<InspectionRequest>> watchPending(String lrId) =>
      _db.collection('lrs').doc(lrId).collection('inspection_requests').where('status', isEqualTo: 'pending').snapshots().map((s) => [for (final d in s.docs) InspectionRequest.fromDoc(d.id, d.data())]);

  // ---- the driver asks ----

  static Future<void> request(Booking b, LrPublic lr, {required String driverName}) async {
    final uid = Backend.requireUid();
    if (tripDriver(b) != uid) throw InspectionException('not_allowed');
    if (lr.issuerId == uid) throw InspectionException('not_allowed');
    final batch = _db.batch();
    final ref = _req(lr.id, uid);
    final existing = await ref.get();
    final data = {'driverId': uid, 'ownerId': lr.issuerId, 'bookingId': lr.bookingId, 'driverName': driverName, 'status': 'pending', 'requestedAt': FieldValue.serverTimestamp()};
    if (existing.exists) {
      batch.update(ref, {'status': 'pending', 'requestedAt': FieldValue.serverTimestamp()});
    } else {
      batch.set(ref, data);
    }
    _logEntry(batch, lr.id, 'requested', uid);
    AuditService.inBatch(batch, AuditType.inspectionRequest, bookingId: lr.bookingId, targetId: lr.issuerId, data: {'lrId': lr.id, 'lrNo': lr.lrNo});
    NotificationService.addInBatch(batch,
        userId: lr.issuerId, type: NotificationType.inspectionRequest, message: '${driverName.isEmpty ? b.assignedDriverName : driverName}: ${lr.lrNo}', relatedId: lr.bookingId);
    await batch.commit();
  }

  // ---- the owner answers ----

  static Future<void> respond(Booking b, LrPublic lr, String driverId, {required bool approve}) async {
    final uid = Backend.requireUid();
    if (lr.issuerId != uid) throw InspectionException('not_allowed');
    final batch = _db.batch();
    final end = now().add(approvalDuration - clockMargin);
    if (approve) {
      final token = await LrService.verifyToken(b, lr);
      batch.set(_grant(lr.id, driverId), _grantMap(uid, driverId, 'approved', end, token));
    }
    batch.update(_req(lr.id, driverId), {'status': approve ? 'approved' : 'denied', 'decidedAt': FieldValue.serverTimestamp()});
    _logEntry(batch, lr.id, approve ? 'approved' : 'denied', driverId, hours: approve ? approvalDuration.inHours : null);
    AuditService.inBatch(batch, approve ? AuditType.inspectionApprove : AuditType.inspectionDeny,
        bookingId: lr.bookingId, targetId: driverId, data: {'lrId': lr.id, 'lrNo': lr.lrNo, if (approve) 'expiresAt': end.toIso8601String()});
    NotificationService.addInBatch(batch,
        userId: driverId,
        type: approve ? NotificationType.inspectionApproved : NotificationType.inspectionDenied,
        message: lr.lrNo,
        relatedId: lr.bookingId);
    await batch.commit();
  }

  /// Before the trip: "Allow inspection for the next N hours" (1 to 72), so the
  /// driver can save the copy and it works without a network.
  static Future<InspectionGrant> allowFor(Booking b, LrPublic lr, int hours) async {
    final uid = Backend.requireUid();
    if (lr.issuerId != uid) throw InspectionException('not_allowed');
    if (hours < 1 || hours > maxAdvance.inHours) throw InspectionException('hours');
    final driver = tripDriver(b);
    if (driver == null || driver == uid) throw InspectionException('no_driver');
    final end = now().add(Duration(hours: hours) - clockMargin);
    final token = await LrService.verifyToken(b, lr);
    final batch = _db.batch();
    batch.set(_grant(lr.id, driver), _grantMap(uid, driver, 'preapproved', end, token));
    _logEntry(batch, lr.id, 'allowed', driver, hours: hours);
    AuditService.inBatch(batch, AuditType.inspectionApprove,
        bookingId: lr.bookingId, targetId: driver, data: {'lrId': lr.id, 'lrNo': lr.lrNo, 'advance': true, 'hours': hours, 'expiresAt': end.toIso8601String()});
    NotificationService.addInBatch(batch, userId: driver, type: NotificationType.inspectionApproved, message: lr.lrNo, relatedId: lr.bookingId);
    await batch.commit();
    return InspectionGrant(driverId: driver, kind: 'preapproved', expiresAt: end, verifyToken: token);
  }

  /// The owner ends a grant early.
  static Future<void> revoke(LrPublic lr, String driverId) async {
    final uid = Backend.requireUid();
    if (lr.issuerId != uid) throw InspectionException('not_allowed');
    final batch = _db.batch();
    batch.delete(_grant(lr.id, driverId));
    _logEntry(batch, lr.id, 'revoked', driverId);
    AuditService.inBatch(batch, AuditType.inspectionDeny, bookingId: lr.bookingId, targetId: driverId, data: {'lrId': lr.id, 'revoked': true});
    await batch.commit();
  }

  static Map<String, Object> _grantMap(String owner, String driver, String kind, DateTime end, String token) => {
        'driverId': driver,
        'ownerId': owner,
        'kind': kind,
        'expiresAt': Timestamp.fromDate(end),
        'verifyToken': token,
        'createdAt': FieldValue.serverTimestamp(),
      };

  // ---- expiry (driver's phone) ----

  /// Called by the driver's screen: when the grant has run out, the cached copy
  /// is deleted and the end is written to the audit log once. Returns true when
  /// something expired.
  static Future<bool> sweep(LrPublic lr, InspectionGrant? grant) async {
    try {
      return await _sweep(lr, grant);
    } catch (_) {
      return false; // storage not ready: the next look tries again
    }
  }

  static Future<bool> _sweep(LrPublic lr, InspectionGrant? grant) async {
    final uid = Backend.uid;
    final cache = InspectionCache();
    final t = now();
    var expired = false;
    if (grant != null && !grant.isValid(t)) {
      expired = true;
      final prefs = await SharedPreferences.getInstance();
      final flag = 'inspection_expired_${lr.id}_${grant.expiresAt.millisecondsSinceEpoch}';
      if (uid != null && prefs.getBool(flag) != true) {
        await prefs.setBool(flag, true);
        try {
          final batch = _db.batch();
          final req = await _req(lr.id, uid).get();
          if (req.exists && req.data()!['status'] == 'approved') {
            batch.update(_req(lr.id, uid), {'status': 'expired', 'decidedAt': FieldValue.serverTimestamp()});
          }
          AuditService.inBatch(batch, AuditType.inspectionExpire, bookingId: lr.bookingId, data: {'lrId': lr.id, 'lrNo': lr.lrNo, 'expiredAt': grant.expiresAt.toIso8601String()});
          await batch.commit();
        } on FirebaseException {
          await prefs.remove(flag); // try again when there is a network
        }
      }
    }
    await cache.purgeExpired(t);
    if (expired) await cache.clear(lr.id);
    return expired;
  }

  // ---- the offline copy ----

  /// The "Inspection copy" PDF: compliance fields, no rate, watermark, LR no,
  /// verify QR (when the owner made one), date and time, driver name.
  static Future<Uint8List> buildCopy(LrBundle bundle, {required String driverName, required AppLanguage language, String verifyToken = ''}) {
    final fields = LrVisibility.snapshot(bundle, LrCopy.driver, grantValid: true);
    return buildLrPdf(LrPdfInput(
      fields: fields,
      copy: LrCopy.driver,
      issuerRole: bundle.pub.issuerRole,
      language: language,
      verifyUrl: verifyToken.isEmpty ? null : LrService.linkFor(verifyToken),
      issuerName: bundle.pub.issuerName,
      delivered: false,
      generatedAt: now(),
      watermark: trLang('inWatermark', language),
      subtitle: '${trLang('inForDriver', language)}: $driverName',
    ));
  }

  /// Builds and keeps the copy on this phone until the grant ends (or for
  /// [showModeCacheTtl] when the owner's mode is `show`). Returns when it will
  /// be deleted, or null when nothing may be saved.
  static Future<DateTime?> saveCopy(LrBundle bundle, {required InspectionGrant? grant, required String driverName, required AppLanguage language}) async {
    final t = now();
    final DateTime end;
    if (grant != null && grant.isValid(t)) {
      end = grant.expiresAt;
    } else if (bundle.pub.complianceMode == ComplianceMode.show && bundle.compliance != null) {
      end = t.add(showModeCacheTtl);
    } else {
      return null;
    }
    final bytes = await buildCopy(bundle, driverName: driverName, language: language, verifyToken: grant?.verifyToken ?? '');
    await InspectionCache().put(bundle.pub.id, bytes, end);
    return end;
  }
}

/// Copies kept in SharedPreferences: `inspection_cache_<lrId>` holds the PDF
/// and the time it must be deleted. Reading an expired copy deletes it.
class InspectionCache {
  static const _prefix = 'inspection_cache_';
  static const _index = 'inspection_cache_index';

  Future<void> put(String lrId, Uint8List bytes, DateTime expiresAt) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('$_prefix$lrId', jsonEncode({'exp': expiresAt.millisecondsSinceEpoch, 'pdf': base64Encode(bytes)}));
    final ids = {...(p.getStringList(_index) ?? const <String>[]), lrId};
    await p.setStringList(_index, ids.toList());
  }

  /// The saved copy, or null (also when it has expired: it is deleted then).
  Future<({Uint8List bytes, DateTime expiresAt})?> get(String lrId, DateTime now) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('$_prefix$lrId');
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final exp = DateTime.fromMillisecondsSinceEpoch(m['exp'] as int);
    if (!exp.isAfter(now)) {
      await clear(lrId);
      return null;
    }
    return (bytes: base64Decode(m['pdf'] as String), expiresAt: exp);
  }

  Future<void> clear(String lrId) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('$_prefix$lrId');
    final ids = (p.getStringList(_index) ?? const <String>[]).where((x) => x != lrId).toList();
    await p.setStringList(_index, ids);
  }

  /// Deletes every copy whose time has come. Run when the app or a trip screen opens.
  Future<int> purgeExpired(DateTime now) async {
    final p = await SharedPreferences.getInstance();
    var n = 0;
    for (final id in List<String>.of(p.getStringList(_index) ?? const <String>[])) {
      final raw = p.getString('$_prefix$id');
      final exp = raw == null ? null : DateTime.fromMillisecondsSinceEpoch((jsonDecode(raw) as Map<String, dynamic>)['exp'] as int);
      if (exp == null || !exp.isAfter(now)) {
        await clear(id);
        n++;
      }
    }
    return n;
  }
}
