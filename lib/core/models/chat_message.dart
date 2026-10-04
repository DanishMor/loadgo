import 'package:cloud_firestore/cloud_firestore.dart';

/// `bookings/{id}/messages/{msgId}`.
class ChatMessage {
  static const maxLength = 500;

  final String id;
  final String senderId;
  final String text;

  /// Looked like it shares contact/payment details (shown with a warning).
  final bool flagged;
  final DateTime? createdAt;

  const ChatMessage({required this.id, required this.senderId, required this.text, this.flagged = false, this.createdAt});

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ChatMessage(
      id: doc.id,
      senderId: d['senderId'] as String? ?? '',
      text: d['text'] as String? ?? '',
      flagged: d['flagged'] == true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
