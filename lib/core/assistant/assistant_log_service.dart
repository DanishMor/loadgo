import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/backend.dart';
import 'assistant_engine.dart';

/// One sentence the assistant did not understand, as an admin sees it.
class UnknownQuestion {
  final String id;
  final String text;
  final String userId;
  final String role;
  final String language;
  final DateTime? createdAt;
  final bool resolved;

  const UnknownQuestion({
    required this.id,
    required this.text,
    required this.userId,
    required this.role,
    required this.language,
    this.createdAt,
    this.resolved = false,
  });

  factory UnknownQuestion.fromDoc(String id, Map<String, dynamic> m) => UnknownQuestion(
        id: id,
        text: (m['text'] ?? '') as String,
        userId: (m['userId'] ?? '') as String,
        role: (m['role'] ?? '') as String,
        language: (m['language'] ?? '') as String,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
        resolved: m['resolved'] == true,
      );
}

/// `assistant_unknown/{id}`: what people asked Sahayak that it could not
/// answer. Rules: create own (text <= 300), only admins read and mark
/// resolved, nobody deletes. The text is cleaned of numbers and links first.
class AssistantLogService {
  AssistantLogService._();

  /// A client-side guard: at most one log every [minGap] per device.
  static const minGap = Duration(seconds: 3);
  static DateTime? _lastLogAt;

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('assistant_unknown');

  /// Forgets the last log time (tests).
  static void resetGuard() => _lastLogAt = null;

  /// Stores [text] when [reply] was not understood. Returns true when a
  /// document was written. Never throws: a failed log must not break the chat.
  static Future<bool> logUnknown(
    String text,
    AssistantReply reply, {
    required String role,
    required String language,
    DateTime Function()? now,
  }) async {
    if (reply.understood) return false;
    final uid = Backend.uid;
    if (uid == null) return false;
    final clean = UnknownQuestionCollector.sanitize(text);
    if (clean.length < 2) return false;
    final at = (now ?? DateTime.now)();
    final last = _lastLogAt;
    if (last != null && at.difference(last) < minGap) return false;
    _lastLogAt = at;
    try {
      await _col.add({
        'text': clean,
        'userId': uid,
        'role': role,
        'language': language,
        'resolved': false,
        'createdAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 180))), // TTL policy, docs/DATA_RETENTION.md
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Newest 100 for the admin screen.
  static Stream<List<UnknownQuestion>> watch() => _col
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => [for (final d in s.docs) UnknownQuestion.fromDoc(d.id, d.data())]);

  static Future<void> resolve(String id) => _col.doc(id).update({
        'resolved': true,
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': Backend.requireUid(),
      });
}
