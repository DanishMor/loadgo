import 'package:cloud_firestore/cloud_firestore.dart';

import '../app_info.dart';
import 'backend.dart';

class FeedbackCategory {
  FeedbackCategory._();
  static const all = ['app', 'booking', 'payment', 'pricing', 'support', 'idea', 'other'];
}

/// Thrown when someone sends feedback again too soon.
class FeedbackTooSoonException implements Exception {
  @override
  String toString() => 'FeedbackTooSoonException';
}

class FeedbackEntry {
  final String id;
  final String userId;
  final String role;
  final int rating;
  final String category;
  final String text;
  final String appVersion;
  final DateTime? createdAt;

  const FeedbackEntry({
    required this.id,
    required this.userId,
    required this.role,
    required this.rating,
    required this.category,
    required this.text,
    required this.appVersion,
    this.createdAt,
  });

  factory FeedbackEntry.fromDoc(String id, Map<String, dynamic> m) => FeedbackEntry(
        id: id,
        userId: (m['userId'] ?? '') as String,
        role: (m['role'] ?? '') as String,
        rating: (m['rating'] as num?)?.toInt() ?? 0,
        category: (m['category'] ?? '') as String,
        text: (m['text'] ?? '') as String,
        appVersion: (m['appVersion'] ?? '') as String,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// `feedback/{id}`: written by the sender, read by super and support admins.
class FeedbackService {
  FeedbackService._();

  /// One feedback per device every [minGap] (a client guard against taps and spam).
  static const minGap = Duration(seconds: 30);
  static DateTime? _lastSentAt;

  static void resetGuard() => _lastSentAt = null;

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('feedback');

  static Future<void> send({required int rating, required String category, String text = '', DateTime Function()? now}) async {
    if (rating < 1 || rating > 5) throw ArgumentError.value(rating, 'rating');
    if (!FeedbackCategory.all.contains(category)) throw ArgumentError.value(category, 'category');
    final clean = text.trim();
    if (clean.length > 500) throw ArgumentError.value(text, 'text', 'at most 500 characters');
    final uid = Backend.requireUid();
    final at = (now ?? DateTime.now)();
    final last = _lastSentAt;
    if (last != null && at.difference(last) < minGap) throw FeedbackTooSoonException();
    final user = (await Backend.db.collection('users').doc(uid).get()).data();
    final role = [user?['role'], user?['selectedRole']].firstWhere((r) => r == 'driver' || r == 'fleet' || r == 'customer', orElse: () => 'customer') as String;
    await _col.add({
      'userId': uid,
      'role': role,
      'rating': rating,
      'category': category,
      'text': clean,
      'appVersion': appVersion,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _lastSentAt = at;
  }

  /// Newest 100 for the admin screen.
  static Stream<List<FeedbackEntry>> watch() => _col
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => [for (final d in s.docs) FeedbackEntry.fromDoc(d.id, d.data())]);
}
