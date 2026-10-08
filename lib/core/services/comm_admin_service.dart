import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_message.dart';
import 'audit_service.dart';
import 'backend.dart';

/// A chat can only be opened for review next to a report or a dispute.
class NoCaseForChatException implements Exception {
  @override
  String toString() => 'NoCaseForChatException';
}

/// Admin side of private chat and calls (Task 68): the violation list,
/// suspensions, opening one chat for a report or dispute, and looking at a
/// phone number. Every look at a number or a chat is written to
/// `audit_events` first. TODO(functions): do the audit from a server so it
/// cannot be skipped.
class CommAdminService {
  CommAdminService._();

  static FirebaseFirestore get _db => Backend.db;

  static const listLimit = 100;

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchViolations() =>
      _db.collection('violations').orderBy('createdAt', descending: true).limit(listLimit).snapshots().map((s) => s.docs);

  static Future<Map<String, dynamic>> user(String uid) async => (await _db.collection('users').doc(uid).get()).data() ?? const {};

  static Future<void> _chatUpdate(String uid, Map<String, Object?> fields, String action) {
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(uid), {...fields, 'updatedAt': FieldValue.serverTimestamp()});
    AuditService.inBatch(batch, AuditType.userAction, targetId: uid, data: {'action': action});
    return batch.commit();
  }

  /// Adds [days] to the suspension (from now when none is running).
  static Future<void> extendSuspension(String uid, {int days = 7, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final current = ((await user(uid))['chatBlockedUntil'] as Timestamp?)?.toDate();
    final base = current != null && current.isAfter(at) ? current : at;
    await _chatUpdate(uid, {'chatBlockedUntil': Timestamp.fromDate(base.add(Duration(days: days)))}, 'chat_suspend_extend');
  }

  static Future<void> liftSuspension(String uid) =>
      _chatUpdate(uid, {'chatBlockedUntil': FieldValue.delete(), 'chatReview': false}, 'chat_suspend_lift');

  static Future<void> resetStrikes(String uid) =>
      _chatUpdate(uid, {'chatStrikes': 0, 'chatReview': false, 'chatStrikeAt': FieldValue.serverTimestamp()}, 'chat_strikes_reset');

  /// Shows the phone numbers of [uids]. The audit line is written first; if it
  /// cannot be written nothing is shown.
  static Future<Map<String, String>> revealPhones(List<String> uids, {String? bookingId}) async {
    for (final uid in uids) {
      await AuditService.record(AuditType.contactView, targetId: uid, bookingId: bookingId, data: {'fields': ['phone']});
    }
    final out = <String, String>{};
    for (final uid in uids) {
      out[uid] = ((await user(uid))['phone'] as String?) ?? '';
    }
    return out;
  }

  /// Opens the chat of [bookingId] for review, resting on a report or a
  /// dispute ticket of the same booking (the rules check that).
  static Future<void> openChatForReview(String bookingId, {String? reportId, String? ticketId}) async {
    if (reportId == null && ticketId == null) throw NoCaseForChatException();
    try {
      await _db.collection('chat_reviews').doc(bookingId).set({
        'by': Backend.requireUid(),
        'reportId': ?reportId,
        'ticketId': ?ticketId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      // Already open (create-only): fine. Not a case for this booking: refused.
      if (e.code == 'permission-denied' && (await _db.collection('chat_reviews').doc(bookingId).get()).exists) {
        // reviewing again
      } else if (e.code == 'permission-denied') {
        throw NoCaseForChatException();
      } else {
        rethrow;
      }
    }
    await AuditService.record(AuditType.chatView, bookingId: bookingId, data: {'reportId': ?reportId, 'ticketId': ?ticketId});
  }

  static Stream<List<ChatMessage>> watchChat(String bookingId) => _db
      .collection('bookings')
      .doc(bookingId)
      .collection('messages')
      .orderBy('createdAt')
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList());
}
