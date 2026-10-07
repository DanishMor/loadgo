import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../chat/off_platform.dart';
import '../models/booking.dart';
import '../models/app_notification.dart';
import '../models/chat_message.dart';
import 'backend.dart';
import 'notification_service.dart';
import 'rate_limit_service.dart';

/// Empty, too long, or the other person blocked you.
class ChatSendException implements Exception {
  final String reason;
  ChatSendException(this.reason);
}

/// Reasons a user can report someone for. Must stay in sync with firestore.rules.
class ReportReason {
  ReportReason._();
  static const abuse = 'abuse';
  static const fraud = 'fraud';
  static const offPlatform = 'off_platform';
  static const other = 'other';
  static const all = [abuse, fraud, offPlatform, other];
}

/// Chat between the customer and driver of one booking.
class ChatService {
  ChatService._();

  static const pageSize = 200;

  static CollectionReference<Map<String, dynamic>> _messages(String bookingId) =>
      Backend.db.collection('bookings').doc(bookingId).collection('messages');

  static DocumentReference<Map<String, dynamic>> _readMark(String bookingId, String uid) =>
      Backend.db.collection('bookings').doc(bookingId).collection('chat_reads').doc(uid);

  static DocumentReference<Map<String, dynamic>> _block(String owner, String other) =>
      Backend.db.collection('users').doc(owner).collection('blocked').doc(other);

  /// The other person in [booking] for the signed-in user.
  static String otherParty(Booking booking) =>
      booking.driverId == Backend.uid ? booking.customerId : booking.driverId;

  /// Oldest first, most recent [pageSize] messages.
  static Stream<List<ChatMessage>> watch(String bookingId) => _messages(bookingId)
      .orderBy('createdAt', descending: true)
      .limit(pageSize)
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList().reversed.toList());

  static Future<void> send(Booking booking, String text) async {
    final uid = Backend.requireUid();
    final t = text.trim();
    if (t.isEmpty) throw ChatSendException('empty');
    if (t.length > ChatMessage.maxLength) throw ChatSendException('tooLong');
    final last = await _lastMessage(booking.id);
    if (last != null && last['senderId'] == uid && isRepeat(last['text'] as String? ?? '', t)) throw ChatSendException('repeat');
    final msgRef = _messages(booking.id).doc();
    final rate = await RateLimit.prepare(RateLimit.messageKind, docId: msgRef.id);
    final notify = _shouldNotify(last, uid);
    try {
      final batch = Backend.db.batch();
      batch.set(msgRef, {
        'senderId': uid,
        'text': t,
        'flagged': looksOffPlatform(t),
        'createdAt': FieldValue.serverTimestamp(),
      });
      rate.addToBatch(batch);
      // N10: the other person gets one in-app notification per burst of messages.
      if (notify) {
        NotificationService.addInBatch(
          batch,
          userId: otherParty(booking),
          type: NotificationType.chatMessage,
          message: '${booking.pickup} → ${booking.drop}',
          relatedId: booking.id,
        );
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      // The rules refuse messages to someone who blocked you.
      if (e.code == 'permission-denied') throw ChatSendException('blocked');
      rethrow;
    }
    await markRead(booking.id);
  }

  /// How long my own messages count as one burst (N10).
  static const notifyBurst = Duration(minutes: 10);

  /// False when the last message of the chat is mine and recent: the other
  /// person was already notified for this burst. LATER(paid): push (FCM sender).
  static bool _shouldNotify(Map<String, dynamic>? last, String uid) {
    if (last == null) return true;
    final at = (last['createdAt'] as Timestamp?)?.toDate();
    return last['senderId'] != uid || at == null || DateTime.now().difference(at) > notifyBurst;
  }

  /// The newest message of the chat, or null (also when it cannot be read).
  static Future<Map<String, dynamic>?> _lastMessage(String bookingId) async {
    try {
      final snap = await _messages(bookingId).orderBy('createdAt', descending: true).limit(1).get();
      return snap.docs.isEmpty ? null : snap.docs.first.data();
    } on FirebaseException {
      return null;
    }
  }

  /// The same text as the sender's previous message (case, spaces and
  /// punctuation at the ends ignored) is a repeat: refused, so a chat cannot
  /// be flooded with one line.
  static bool isRepeat(String previous, String next) {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^[\s\p{P}]+|[\s\p{P}]+$', unicode: true), '');
    final a = norm(previous), b = norm(next);
    return a.isNotEmpty && a == b;
  }

  static Future<void> markRead(String bookingId) async {
    final uid = Backend.uid;
    if (uid == null) return;
    await _readMark(bookingId, uid).set({'lastReadAt': FieldValue.serverTimestamp()});
  }

  /// Messages from the other person newer than my last read mark.
  static Stream<int> watchUnread(String bookingId) {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(0);
    DateTime? lastRead;
    List<ChatMessage>? messages;
    var readLoaded = false;
    int count() => messages!
        .where((m) => m.senderId != uid && (lastRead == null || (m.createdAt != null && m.createdAt!.isAfter(lastRead!))))
        .length;
    late final StreamController<int> out;
    final subs = <StreamSubscription<Object?>>[];
    out = StreamController<int>(
      onListen: () {
        // Emit only once both the read mark and the messages have arrived.
        void emit() {
          if (readLoaded && messages != null) out.add(count());
        }
        subs.add(_readMark(bookingId, uid).snapshots().listen((s) {
          lastRead = (s.data()?['lastReadAt'] as Timestamp?)?.toDate();
          readLoaded = true;
          emit();
        }, onError: out.addError));
        subs.add(watch(bookingId).listen((m) {
          messages = m;
          emit();
        }, onError: out.addError));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream.distinct();
  }

  static Future<void> block(String otherUid) =>
      _block(Backend.requireUid(), otherUid).set({'createdAt': FieldValue.serverTimestamp()});

  static Future<void> unblock(String otherUid) => _block(Backend.requireUid(), otherUid).delete();

  static Stream<bool> watchBlocked(String otherUid) {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(false);
    return _block(uid, otherUid).snapshots().map((s) => s.exists);
  }

  /// Reports the other party of [booking] (reviewed by admins).
  static Future<void> report(Booking booking, {required String reason, String details = '', String? messageId}) async {
    final uid = Backend.requireUid();
    await Backend.db.collection('reports').add({
      'reporterId': uid,
      'reportedId': otherParty(booking),
      'bookingId': booking.id,
      'reason': reason,
      'details': details.trim(),
      'messageId': ?messageId,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
