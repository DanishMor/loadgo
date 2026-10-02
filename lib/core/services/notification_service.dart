import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import 'backend.dart';

class NotificationService {
  NotificationService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      Backend.db.collection('notifications');

  /// Adds a notification for [userId] to an in-flight transaction, so it is
  /// written atomically with the event it describes.
  static void addInTransaction(
    Transaction tx, {
    required String userId,
    required String type,
    required String message,
    required String relatedId,
    String? status,
  }) {
    tx.set(_col.doc(), {
      'userId': userId,
      'type': type,
      'message': message,
      'relatedId': relatedId,
      'status': ?status,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// The signed-in user's notifications, newest first.
  static Stream<List<AppNotification>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('userId', isEqualTo: uid).snapshots().map((snap) {
      final list = snap.docs.map(AppNotification.fromDoc).toList();
      list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
      return list;
    });
  }

  static Stream<int> watchUnreadCount() =>
      watchMine().map((list) => list.where((n) => !n.read).length);

  static Future<void> markRead(String id) => _col.doc(id).update({'read': true});

  static Future<void> markAllRead(Iterable<AppNotification> notifications) async {
    final unread = notifications.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    final batch = Backend.db.batch();
    for (final n in unread) {
      batch.update(_col.doc(n.id), {'read': true});
    }
    await batch.commit();
  }
}
