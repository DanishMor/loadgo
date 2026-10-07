import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/risk.dart';
import 'audit_service.dart';
import 'backend.dart';

class UserActionException implements Exception {
  /// 'reason' (a suspend or ban needs a reason), 'self' (not on yourself), 'state' (nothing to change), 'note'.
  final String reason;
  UserActionException(this.reason);
  @override
  String toString() => 'UserActionException($reason)';
}

class UserAction {
  UserAction._();
  static const suspend = 'suspend';
  static const ban = 'ban';
  static const unban = 'unban';
  static const reverify = 'reverify';
  static const note = 'note';
  static const flag = 'flag';
  static const unflag = 'unflag';
  static const bulkHold = 'bulk_hold';
  static const bulkUnhold = 'bulk_unhold';
  static const bulkStatus = 'bulk_status';
}

/// What a bulk change did.
class BulkResult {
  final int changed;
  final int skipped;
  const BulkResult(this.changed, this.skipped);
}

class ReviewKind {
  ReviewKind._();
  static const name = 'name';
  static const rcOwner = 'rc_owner';
  static const vehicle = 'vehicle';
  static const document = 'document';
  static const other = 'other';
  static const all = [name, rcOwner, vehicle, document, other];
}

/// One line of the admin action history of a user (from `audit_events`).
class UserActionEvent {
  final String action;
  final String actorId;
  final String reason;
  final DateTime? at;
  const UserActionEvent({required this.action, required this.actorId, required this.reason, this.at});
}

class AdminNote {
  final String id;
  final String by;
  final String text;
  final DateTime? createdAt;
  const AdminNote({required this.id, required this.by, required this.text, this.createdAt});
}

/// Admin user management: suspend, ban, restore, force re-verification and
/// internal notes. Every action is written to `audit_events` in the same
/// batch (type `user_action`). The rules make all of it admin-only.
class AdminUserService {
  AdminUserService._();

  static DocumentReference<Map<String, dynamic>> _user(String uid) => Backend.db.collection('users').doc(uid);

  static const tierFor = {UserAction.suspend: RiskTier.suspended, UserAction.ban: RiskTier.banned, UserAction.unban: RiskTier.normal};

  /// suspend / ban need a reason of 3+ characters; unban clears the tier.
  static Future<void> setStanding(String uid, String action, {String reason = ''}) async {
    final tier = tierFor[action];
    if (tier == null) throw ArgumentError.value(action, 'action');
    final me = Backend.requireUid();
    if (uid == me) throw UserActionException('self');
    final r = reason.trim();
    if (action != UserAction.unban && r.length < 3) throw UserActionException('reason');
    final current = (await _user(uid).get()).data()?['riskTier'] as String? ?? RiskTier.normal;
    if (current == tier) throw UserActionException('state');
    final batch = Backend.db.batch();
    batch.update(_user(uid), {
      'riskTier': tier,
      'riskReason': r,
      'riskUpdatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.userAction, targetId: uid, data: {'action': action, 'reason': r, 'from': current, 'to': tier});
    await batch.commit();
  }

  /// Tiers a bulk change may set (a ban is always one person, with a reason).
  static const bulkTiers = [RiskTier.normal, RiskTier.review, RiskTier.restricted, RiskTier.suspended];

  /// Sets [tier] on many users at once (hold = restricted, unhold = back to
  /// normal, or any of [bulkTiers] for "set status"). [current] maps each uid
  /// to the tier it has now. Skipped: yourself, banned users, users already on
  /// [tier], and for [UserAction.bulkUnhold] users that are not restricted.
  /// A hold or status change needs a reason of 3+ characters. One audit row
  /// (type `user_action`, `bulk: true`) per user in the same batch, 100 users
  /// per batch.
  static Future<BulkResult> bulkSetTier(Map<String, String> current, String tier, {required String action, String reason = ''}) async {
    if (!bulkTiers.contains(tier)) throw ArgumentError.value(tier, 'tier');
    if (action != UserAction.bulkHold && action != UserAction.bulkUnhold && action != UserAction.bulkStatus) throw ArgumentError.value(action, 'action');
    final me = Backend.requireUid();
    final r = reason.trim();
    if (action != UserAction.bulkUnhold && r.length < 3) throw UserActionException('reason');
    final targets = <String, String>{
      for (final e in current.entries)
        if (e.key != me && e.value != RiskTier.banned && e.value != tier && (action != UserAction.bulkUnhold || e.value == RiskTier.restricted)) e.key: e.value,
    };
    final uids = targets.keys.toList();
    for (var i = 0; i < uids.length; i += 100) {
      final batch = Backend.db.batch();
      for (final uid in uids.skip(i).take(100)) {
        batch.update(_user(uid), {'riskTier': tier, 'riskReason': r, 'riskUpdatedAt': FieldValue.serverTimestamp()});
        AuditService.inBatch(batch, AuditType.userAction, targetId: uid, data: {'action': action, 'reason': r, 'from': targets[uid], 'to': tier, 'bulk': true});
      }
      await batch.commit();
    }
    return BulkResult(uids.length, current.length - uids.length);
  }

  /// Sends a driver back to "pending": they cannot take loads until an admin
  /// approves them again in Driver verification.
  static Future<void> forceReverify(String uid, {String reason = ''}) async {
    final r = reason.trim();
    if (r.length < 3) throw UserActionException('reason');
    final me = Backend.requireUid();
    final batch = Backend.db.batch();
    batch.update(_user(uid), {
      'verified': false,
      'verificationStatus': 'pending',
      'verificationMeta': {'source': 'manual_review', 'by': me, 'status': 'pending', 'at': FieldValue.serverTimestamp()},
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.userAction, targetId: uid, data: {'action': UserAction.reverify, 'reason': r});
    await batch.commit();
  }

  /// K13: marks a mismatch (name, RC owner, vehicle...) so the profile needs a
  /// manual look. The driver sees the note on Home; clear it when settled.
  static Future<void> setReviewFlag(String uid, String kind, String note) async {
    final n = note.trim();
    if (!ReviewKind.all.contains(kind)) throw ArgumentError.value(kind, 'kind');
    if (n.length < 3) throw UserActionException('reason');
    final me = Backend.requireUid();
    final batch = Backend.db.batch();
    batch.update(_user(uid), {
      'reviewFlag': {'kind': kind, 'note': n, 'by': me, 'at': FieldValue.serverTimestamp()},
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.userAction, targetId: uid, data: {'action': UserAction.flag, 'reason': '$kind: $n'});
    await batch.commit();
  }

  static Future<void> clearReviewFlag(String uid) async {
    final batch = Backend.db.batch();
    batch.update(_user(uid), {'reviewFlag': FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()});
    AuditService.inBatch(batch, AuditType.userAction, targetId: uid, data: {'action': UserAction.unflag, 'reason': ''});
    await batch.commit();
  }

  static Future<void> addNote(String uid, String text) async {
    final t = text.trim();
    if (t.isEmpty || t.length > 1000) throw UserActionException('note');
    final batch = Backend.db.batch();
    final ref = _user(uid).collection('admin_notes').doc();
    batch.set(ref, {'by': Backend.requireUid(), 'text': t, 'createdAt': FieldValue.serverTimestamp()});
    AuditService.inBatch(batch, AuditType.userAction, targetId: uid, data: {'action': UserAction.note, 'reason': '', 'noteId': ref.id});
    await batch.commit();
  }

  static Stream<List<AdminNote>> watchNotes(String uid) => _user(uid).collection('admin_notes').snapshots().map((s) {
        final list = [
          for (final d in s.docs)
            AdminNote(id: d.id, by: d.data()['by'] as String? ?? '', text: d.data()['text'] as String? ?? '', createdAt: (d.data()['createdAt'] as Timestamp?)?.toDate()),
        ];
        list.sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
        return list;
      });

  /// Admin actions on [uid], newest first.
  static Stream<List<UserActionEvent>> watchHistory(String uid) =>
      Backend.db.collection('audit_events').where('targetId', isEqualTo: uid).snapshots().map((s) {
        final list = <UserActionEvent>[];
        for (final d in s.docs) {
          final m = d.data();
          if (m['type'] != AuditType.userAction) continue;
          final data = (m['data'] as Map?) ?? const {};
          list.add(UserActionEvent(
            action: data['action'] as String? ?? '',
            actorId: m['actorId'] as String? ?? '',
            reason: data['reason'] as String? ?? '',
            at: (m['createdAt'] as Timestamp?)?.toDate(),
          ));
        }
        list.sort((a, b) => (b.at ?? DateTime(3000)).compareTo(a.at ?? DateTime(3000)));
        return list;
      });

  static Stream<Map<String, dynamic>?> watchUser(String uid) => _user(uid).snapshots().map((s) => s.data());
}
