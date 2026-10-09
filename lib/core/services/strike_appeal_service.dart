import 'package:cloud_firestore/cloud_firestore.dart';

import '../comm/chat_strikes.dart';
import 'audit_service.dart';
import 'backend.dart';
import 'server_clock.dart';

/// `strike_appeals/{violationId}`: a person asks an admin to look at one strike again.
class StrikeAppeal {
  final String violationId;
  final String userId;
  final String text;
  final String status; // pending, granted, rejected
  final String note;
  final DateTime? createdAt;
  const StrikeAppeal({required this.violationId, required this.userId, required this.text, required this.status, this.note = '', this.createdAt});

  bool get pending => status == 'pending';

  factory StrikeAppeal.fromDoc(String id, Map<String, dynamic> d) => StrikeAppeal(
        violationId: id,
        userId: d['userId'] as String? ?? '',
        text: d['text'] as String? ?? '',
        status: d['status'] as String? ?? 'pending',
        note: d['note'] as String? ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// A strike a person received (one `violations` document).
class MyStrike {
  final String id;
  final String kind;
  final String excerpt;
  final DateTime? at;
  final StrikeAppeal? appeal;
  const MyStrike({required this.id, required this.kind, required this.excerpt, required this.at, this.appeal});

  /// Can still be appealed: not appealed yet, and inside the window.
  bool canAppeal(DateTime now) => appeal == null && at != null && AppealOutcome.open(at!, now);
}

class AppealException implements Exception {
  /// 'text' (10 to 300 characters), 'closed' (too long ago), 'exists'.
  final String reason;
  AppealException(this.reason);
  @override
  String toString() => 'AppealException($reason)';
}

class StrikeAppealService {
  StrikeAppealService._();

  static FirebaseFirestore get _db => Backend.db;
  static CollectionReference<Map<String, dynamic>> get _col => _db.collection('strike_appeals');

  static const minText = 10;
  static const maxText = 300;

  /// The person's newest strikes (up to 10) with their appeal, if any.
  static Future<List<MyStrike>> mine() async {
    final uid = Backend.requireUid();
    final v = await _db.collection('violations').where('userId', isEqualTo: uid).limit(10).get();
    final a = await _col.where('userId', isEqualTo: uid).limit(20).get();
    final appeals = {for (final d in a.docs) d.id: StrikeAppeal.fromDoc(d.id, d.data())};
    final out = [
      for (final d in v.docs)
        MyStrike(id: d.id, kind: '${d.data()['kind'] ?? ''}', excerpt: '${d.data()['excerpt'] ?? ''}', at: (d.data()['createdAt'] as Timestamp?)?.toDate(), appeal: appeals[d.id]),
    ]..sort((x, y) => (y.at ?? DateTime(1970)).compareTo(x.at ?? DateTime(1970)));
    return out;
  }

  static Future<void> appeal(MyStrike strike, String text, {DateTime? now}) async {
    final uid = Backend.requireUid();
    final t = text.trim();
    if (t.length < minText || t.length > maxText) throw AppealException('text');
    if (strike.appeal != null) throw AppealException('exists');
    if (!strike.canAppeal(now ?? ServerClock.now())) throw AppealException('closed');
    try {
      await _col.doc(strike.id).set({'userId': uid, 'violationId': strike.id, 'text': t, 'status': 'pending', 'createdAt': FieldValue.serverTimestamp()});
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw AppealException('exists');
      rethrow;
    }
  }

  // ---- admin ----

  static Stream<List<StrikeAppeal>> watchPending() => _col.where('status', isEqualTo: 'pending').limit(100).snapshots().map((s) => [for (final d in s.docs) StrikeAppeal.fromDoc(d.id, d.data())]);

  /// Grants (one strike off, suspension and review lifted when the lower count no
  /// longer needs them) or rejects an appeal, with a short note, audited.
  static Future<void> decide(StrikeAppeal a, {required bool grant, String note = ''}) async {
    final me = Backend.requireUid();
    final n = note.trim().length > 200 ? note.trim().substring(0, 200) : note.trim();
    final batch = _db.batch();
    batch.update(_col.doc(a.violationId), {'status': grant ? 'granted' : 'rejected', 'handledBy': me, 'handledAt': FieldValue.serverTimestamp(), if (n.isNotEmpty) 'note': n});
    if (grant) {
      final user = await _db.collection('users').doc(a.userId).get();
      final out = AppealOutcome.grant((user.data()?['chatStrikes'] as num?)?.toInt() ?? 0);
      batch.update(_db.collection('users').doc(a.userId), {
        'chatStrikes': out.strikes,
        if (out.liftBlock) 'chatBlockedUntil': FieldValue.delete(),
        if (out.clearReview) 'chatReview': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    AuditService.inBatch(batch, AuditType.userAction, targetId: a.userId, data: {'action': grant ? 'strike_appeal_granted' : 'strike_appeal_rejected', 'collection': 'strike_appeals', 'violationId': a.violationId});
    await batch.commit();
  }
}
