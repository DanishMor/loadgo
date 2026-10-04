import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationType {
  NotificationType._();
  static const loadAccepted = 'load_accepted';
  static const statusChanged = 'status_changed';
  static const ratingReceived = 'rating_received';
  static const bookingCancelled = 'booking_cancelled';
  static const breakdownReported = 'breakdown_reported';

  /// Must stay in sync with firestore.rules.
  static const all = [loadAccepted, statusChanged, ratingReceived, bookingCancelled, breakdownReported];
}

class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String message;

  /// Booking the notification is about.
  final String relatedId;

  /// New booking status for [NotificationType.statusChanged].
  final String? status;
  final bool read;
  final Timestamp? createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.message,
    required this.relatedId,
    required this.read,
    this.status,
    this.createdAt,
  });

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AppNotification(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      type: d['type'] as String? ?? '',
      message: d['message'] as String? ?? '',
      relatedId: d['relatedId'] as String? ?? '',
      status: d['status'] as String?,
      read: d['read'] == true,
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}
