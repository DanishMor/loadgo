import 'package:cloud_firestore/cloud_firestore.dart';

/// Must stay in sync with firestore.rules.
class TicketCategory {
  TicketCategory._();
  static const bookingIssue = 'booking_issue';
  static const payment = 'payment';
  static const account = 'account';
  static const safety = 'safety';

  /// Needs a booking.
  static const dispute = 'dispute';
  static const other = 'other';
  static const all = [bookingIssue, payment, dispute, safety, account, other];
}

class TicketPriority {
  TicketPriority._();
  static const low = 'low';
  static const normal = 'normal';
  static const high = 'high';
  static const urgent = 'urgent';
  static const all = [low, normal, high, urgent];
}

class TicketStatus {
  TicketStatus._();
  static const open = 'open';
  static const inProgress = 'in_progress';
  static const resolved = 'resolved';
  static const closed = 'closed';
  static const all = [open, inProgress, resolved, closed];
}

/// `tickets/{id}`.
class SupportTicket {
  static const maxEscalation = 3;

  final String id;
  final String userId;
  final String category;
  final String priority;
  final String status;
  final String subject;
  final String description;
  final String? bookingId;
  final int escalationLevel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SupportTicket({
    required this.id,
    required this.userId,
    required this.category,
    required this.priority,
    required this.status,
    required this.subject,
    this.description = '',
    this.bookingId,
    this.escalationLevel = 0,
    this.createdAt,
    this.updatedAt,
  });

  bool get isOpen => status == TicketStatus.open || status == TicketStatus.inProgress;

  bool get canEscalate => isOpen && escalationLevel < maxEscalation;

  factory SupportTicket.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SupportTicket(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      category: d['category'] as String? ?? TicketCategory.other,
      priority: d['priority'] as String? ?? TicketPriority.normal,
      status: d['status'] as String? ?? TicketStatus.open,
      subject: d['subject'] as String? ?? '',
      description: d['description'] as String? ?? '',
      bookingId: d['bookingId'] as String?,
      escalationLevel: (d['escalationLevel'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// `tickets/{id}/replies/{replyId}`.
class TicketReply {
  final String id;
  final String authorId;
  final String text;
  final bool fromAdmin;
  final DateTime? createdAt;

  const TicketReply({required this.id, required this.authorId, required this.text, this.fromAdmin = false, this.createdAt});

  factory TicketReply.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return TicketReply(
      id: doc.id,
      authorId: d['authorId'] as String? ?? '',
      text: d['text'] as String? ?? '',
      fromAdmin: d['fromAdmin'] == true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
