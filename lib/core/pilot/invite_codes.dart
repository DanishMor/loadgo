import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/audit_service.dart';
import '../services/backend.dart';
import '../services/server_clock.dart';

/// Why a code was or was not accepted.
enum InviteCheck { ok, unknown, wrongRole, expired, usedUp, off }

/// Pilot invite code (MASTER-6 Task 1): `invite_codes/{code}`. The admin makes
/// it for a role (or any role) and optionally a route label, with a number of
/// uses and a last day. In pilot mode (`config/pilot.inviteOnly`) a new person
/// needs a code or a place on `pilot_whitelist` before the profile screens.
class InviteCode {
  final String code;
  final String role; // any | customer | driver | fleet
  final String route;
  final int maxUses;
  final int uses;
  final DateTime? expiresAt;
  final bool active;

  const InviteCode({required this.code, this.role = 'any', this.route = '', this.maxUses = 1, this.uses = 0, this.expiresAt, this.active = true});

  static const roles = ['any', 'customer', 'driver', 'fleet'];
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0 O 1 I
  static const codeLength = 8;

  /// Upper case, letters and digits only ("ab-12 cd" -> "AB12CD").
  static String normalise(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String generate([Random? rnd]) {
    final r = rnd ?? Random.secure();
    return String.fromCharCodes([for (var i = 0; i < codeLength; i++) alphabet.codeUnitAt(r.nextInt(alphabet.length))]);
  }

  static InviteCode? fromDoc(String id, Map<String, dynamic>? m) {
    if (m == null) return null;
    int n(Object? v, int d) => v is num ? v.toInt() : d;
    final exp = m['expiresAt'];
    final role = '${m['role'] ?? 'any'}';
    return InviteCode(
      code: id,
      role: roles.contains(role) ? role : 'any',
      route: '${m['route'] ?? ''}',
      maxUses: n(m['maxUses'], 1),
      uses: n(m['uses'], 0),
      expiresAt: exp is Timestamp ? exp.toDate() : null,
      active: m['active'] != false,
    );
  }

  /// [now] should be the server clock (`ServerClock.now()`).
  InviteCheck check({required String forRole, required DateTime now}) {
    if (!active) return InviteCheck.off;
    if (role != 'any' && role != forRole) return InviteCheck.wrongRole;
    if (expiresAt != null && !now.isBefore(expiresAt!)) return InviteCheck.expired;
    if (uses >= maxUses) return InviteCheck.usedUp;
    return InviteCheck.ok;
  }

  int get left => (maxUses - uses).clamp(0, maxUses);
}

class InviteService {
  InviteService._();

  static FirebaseFirestore get _db => Backend.db;

  /// Pilot switch from `config/pilot` (off when the document is missing).
  static Future<bool> inviteOnly() async {
    try {
      final d = await _db.collection('config').doc('pilot').get();
      return d.data()?['inviteOnly'] == true;
    } catch (_) {
      return false; // a read failure must not lock everybody out
    }
  }

  static String _digits(String? phone) => (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  /// Whether this signed-in phone is on `pilot_whitelist/{digits}`.
  static Future<bool> whitelisted(String? phone) async {
    final id = _digits(phone);
    if (id.isEmpty) return false;
    try {
      return (await _db.collection('pilot_whitelist').doc(id).get()).exists;
    } catch (_) {
      return false;
    }
  }

  /// This person already used a code (`invite_redemptions/{uid}`).
  static Future<bool> redeemed(String uid) async {
    try {
      return (await _db.collection('invite_redemptions').doc(uid).get()).exists;
    } catch (_) {
      return false;
    }
  }

  /// True when the person may continue to the profile screens.
  static Future<bool> mayJoin({required String uid, required String? phone}) async {
    if (!await inviteOnly()) return true;
    return await redeemed(uid) || await whitelisted(phone);
  }

  /// Use a code: one transaction raises `uses` and writes the redemption.
  static Future<InviteCheck> redeem(String raw, {required String role}) async {
    final uid = Backend.requireUid();
    final code = InviteCode.normalise(raw);
    if (code.length != InviteCode.codeLength) return InviteCheck.unknown;
    final ref = _db.collection('invite_codes').doc(code);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final invite = InviteCode.fromDoc(code, snap.data());
      if (invite == null) return InviteCheck.unknown;
      final res = invite.check(forRole: role, now: ServerClock.now());
      if (res != InviteCheck.ok) return res;
      tx.update(ref, {'uses': invite.uses + 1});
      tx.set(_db.collection('invite_redemptions').doc(uid), {'code': code, 'role': role, 'createdAt': FieldValue.serverTimestamp()});
      return InviteCheck.ok;
    });
  }

  // ---- admin ----

  static Future<String> create({required String role, String route = '', int maxUses = 1, int days = 30}) async {
    assert(InviteCode.roles.contains(role) && maxUses >= 1 && maxUses <= 1000 && days >= 1 && days <= 365);
    final uid = Backend.requireUid();
    final code = InviteCode.generate();
    final batch = _db.batch();
    batch.set(_db.collection('invite_codes').doc(code), {
      'role': role,
      'route': route.trim(),
      'maxUses': maxUses,
      'uses': 0,
      'expiresAt': Timestamp.fromDate(ServerClock.now().add(Duration(days: days))),
      'active': true,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.userAction, targetId: code, data: {'action': 'invite_create', 'collection': 'invite_codes', 'role': role, 'maxUses': maxUses});
    await batch.commit();
    return code;
  }

  static Future<void> setActive(String code, bool active) {
    final batch = _db.batch();
    batch.update(_db.collection('invite_codes').doc(code), {'active': active});
    AuditService.inBatch(batch, AuditType.userAction, targetId: code, data: {'action': 'invite_active', 'collection': 'invite_codes', 'active': active});
    return batch.commit();
  }

  static Future<List<InviteCode>> list({int limit = 100}) async {
    final snap = await _db.collection('invite_codes').orderBy('createdAt', descending: true).limit(limit).get();
    return [for (final d in snap.docs) InviteCode.fromDoc(d.id, d.data())!];
  }

  static Future<void> addWhitelist(String phone) {
    final id = _digits(phone);
    final batch = _db.batch();
    batch.set(_db.collection('pilot_whitelist').doc(id), {'createdBy': Backend.requireUid(), 'createdAt': FieldValue.serverTimestamp()});
    AuditService.inBatch(batch, AuditType.userAction, targetId: id, data: {'action': 'whitelist_add', 'collection': 'pilot_whitelist'});
    return batch.commit();
  }
}
