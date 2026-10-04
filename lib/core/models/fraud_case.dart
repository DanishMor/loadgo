import 'package:cloud_firestore/cloud_firestore.dart';

/// `fraud_cases/{id}`: one investigation about one user, opened by an admin
/// from a report or by hand. Alert -> evidence (reports, notes) -> analyst
/// action (risk tier) -> resolution. Admin-only collection.
class FraudCase {
  final String id;
  final String userId;
  final String summary;
  final String status;
  final List<String> reportIds;
  final String? outcome;
  final DateTime? createdAt;

  const FraudCase({
    required this.id,
    required this.userId,
    required this.summary,
    required this.status,
    this.reportIds = const [],
    this.outcome,
    this.createdAt,
  });

  static const open = 'open';
  static const investigating = 'investigating';
  static const resolved = 'resolved';
  static const dismissed = 'dismissed';
  static const statuses = [open, investigating, resolved, dismissed];

  /// What was decided when the case was closed.
  static const outcomeNoAction = 'no_action';
  static const outcomeWarned = 'warned';
  static const outcomeRestricted = 'restricted';
  static const outcomeSuspended = 'suspended';
  static const outcomes = [outcomeNoAction, outcomeWarned, outcomeRestricted, outcomeSuspended];

  bool get isClosed => status == resolved || status == dismissed;

  factory FraudCase.fromDoc(String id, Map<String, dynamic> d) => FraudCase(
        id: id,
        userId: d['userId'] as String? ?? '',
        summary: d['summary'] as String? ?? '',
        status: d['status'] as String? ?? open,
        reportIds: [for (final r in (d['reportIds'] as List?) ?? const []) r.toString()],
        outcome: d['outcome'] as String?,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}

class CaseNote {
  final String id;
  final String by;
  final String text;
  final DateTime? createdAt;
  const CaseNote({required this.id, required this.by, required this.text, this.createdAt});

  factory CaseNote.fromDoc(String id, Map<String, dynamic> d) => CaseNote(
        id: id,
        by: d['by'] as String? ?? '',
        text: d['text'] as String? ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}
