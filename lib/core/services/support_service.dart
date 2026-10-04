import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/support_ticket.dart';
import 'backend.dart';

/// Help desk tickets. Users open, reply, escalate and close their own
/// tickets; admins change status/priority and reply (Task 12 screens).
class SupportService {
  SupportService._();

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('tickets');

  static Future<String> create({
    required String category,
    required String subject,
    String description = '',
    String priority = TicketPriority.normal,
    String? bookingId,
  }) async {
    final uid = Backend.requireUid();
    if (category == TicketCategory.dispute && bookingId == null) {
      throw ArgumentError('A dispute needs a booking');
    }
    final ref = await _col.add({
      'userId': uid,
      'category': category,
      'priority': category == TicketCategory.safety ? TicketPriority.urgent : priority,
      'status': TicketStatus.open,
      'subject': subject.trim(),
      'description': description.trim(),
      'bookingId': ?bookingId,
      'escalationLevel': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Stream<List<SupportTicket>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('userId', isEqualTo: uid).snapshots().map((s) {
      final list = s.docs.map(SupportTicket.fromDoc).toList();
      list.sort((a, b) => (b.updatedAt ?? DateTime(3000)).compareTo(a.updatedAt ?? DateTime(3000)));
      return list;
    });
  }

  static Stream<SupportTicket?> watch(String id) =>
      _col.doc(id).snapshots().map((s) => s.exists ? SupportTicket.fromDoc(s) : null);

  static Stream<List<TicketReply>> watchReplies(String id) => _col
      .doc(id)
      .collection('replies')
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map(TicketReply.fromDoc).toList());

  static Future<void> reply(String id, String text, {bool asAdmin = false}) async {
    final t = text.trim();
    if (t.isEmpty || t.length > 1000) throw ArgumentError.value(text, 'text');
    await _col.doc(id).collection('replies').add({
      'authorId': Backend.requireUid(),
      'text': t,
      'fromAdmin': asAdmin,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Raises the escalation level by one (max [SupportTicket.maxEscalation]).
  static Future<void> escalate(SupportTicket t) {
    if (!t.canEscalate) throw StateError('Cannot escalate');
    return _col.doc(t.id).update({'escalationLevel': t.escalationLevel + 1, 'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> close(String id) =>
      _col.doc(id).update({'status': TicketStatus.closed, 'updatedAt': FieldValue.serverTimestamp()});
}
