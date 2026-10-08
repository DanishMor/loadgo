import 'package:cloud_firestore/cloud_firestore.dart';

import '../comm/chat_strikes.dart';
import '../comm/contact_filter.dart';
import 'analytics_events.dart';
import 'backend.dart';

/// Chat and calls are off for this person until [until].
class ChatBlockedException implements Exception {
  final DateTime until;
  const ChatBlockedException(this.until);

  @override
  String toString() => 'ChatBlockedException($until)';
}

/// What happened when a message was stopped.
class ViolationOutcome {
  final ContactKind kind;
  final int strikes;

  /// Set when this strike switched chat and calls off.
  final DateTime? blockedUntil;
  final bool review;

  /// False when the strike could not be written (offline, a wrong phone
  /// clock): the message is still not sent.
  final bool recorded;

  const ViolationOutcome({required this.kind, required this.strikes, this.blockedUntil, this.review = false, this.recorded = true});

  bool get warningOnly => blockedUntil == null;
}

/// The message was stopped because it carried contact or payment details.
class ChatContactException implements Exception {
  final ViolationOutcome outcome;
  const ChatContactException(this.outcome);

  @override
  String toString() => 'ChatContactException(${outcome.kind.name}, strikes ${outcome.strikes})';
}

/// Strikes, suspensions and the violation log (Task 68). A stopped message
/// writes `violations/{uid}_{seq}` and raises `users.chatStrikes` by one in
/// the same batch; the rules check the id, the count and the ladder. Records
/// only. TODO(functions): do this server side so a modified app cannot skip it.
class CommGuard {
  CommGuard._();

  static FirebaseFirestore get _db => Backend.db;

  static DateTime _date(Object? v) => v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);

  static Future<ChatStatus> status([String? uid]) async {
    final id = uid ?? Backend.requireUid();
    final snap = await _db.collection('users').doc(id).get();
    return ChatStatus.fromUser(snap.data(), _date);
  }

  static Stream<ChatStatus> watch() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const ChatStatus());
    return _db.collection('users').doc(uid).snapshots().map((s) => ChatStatus.fromUser(s.data(), _date));
  }

  /// Throws [ChatBlockedException] while chat and calls are off.
  static Future<ChatStatus> ensureAllowed({DateTime? now}) async {
    final s = await status();
    if (s.isBlocked(now ?? DateTime.now())) throw ChatBlockedException(s.blockedUntil!);
    return s;
  }

  /// Records one stopped message. Never throws: when the write fails the
  /// person still gets the warning and the message is still not sent.
  static Future<ViolationOutcome> recordViolation({required String bookingId, required ContactKind kind, required String text, DateTime? now}) async {
    final uid = Backend.requireUid();
    final at = now ?? DateTime.now();
    ChatStatus before;
    try {
      before = await status(uid);
    } catch (_) {
      return ViolationOutcome(kind: kind, strikes: 0, recorded: false);
    }
    final strikes = before.strikes + 1;
    final seq = before.seq + 1;
    final block = ChatLadder.blockFor(strikes);
    final until = block == null ? null : at.add(block);
    final review = ChatLadder.needsReview(strikes);
    final excerpt = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    try {
      final batch = _db.batch();
      batch.set(_db.collection('violations').doc('${uid}_$seq'), {
        'userId': uid,
        'bookingId': bookingId,
        'kind': kind.name,
        'excerpt': excerpt.length > 120 ? excerpt.substring(0, 120) : excerpt,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(_db.collection('users').doc(uid), {
        'chatStrikes': strikes,
        'chatSeq': seq,
        'chatStrikeAt': FieldValue.serverTimestamp(),
        'chatBlockedUntil': ?(until == null ? null : Timestamp.fromDate(until)),
        if (review) 'chatReview': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      AnalyticsEvents.log(AnalyticsEvents.contactBlocked, params: {'kind': kind.name, 'strikes': strikes});
      return ViolationOutcome(kind: kind, strikes: strikes, blockedUntil: until, review: review);
    } catch (_) {
      return ViolationOutcome(kind: kind, strikes: before.strikes, recorded: false);
    }
  }

  /// Takes one strike off after 30 clean days. Quiet when not due or when it
  /// cannot be written. Call when the chat opens.
  static Future<bool> decayIfDue({DateTime? now}) async {
    try {
      final uid = Backend.uid;
      if (uid == null) return false;
      final s = await status(uid);
      if (!ChatLadder.canDecay(strikes: s.strikes, lastChange: s.strikeAt, now: now ?? DateTime.now())) return false;
      await _db.collection('users').doc(uid).update({
        'chatStrikes': s.strikes - 1,
        'chatStrikeAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
