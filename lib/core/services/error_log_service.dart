import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../app_info.dart';
import 'backend.dart';

class AppError {
  final String id;
  final String message;
  final String screen;
  final String kind;
  final String appVersion;
  final DateTime? createdAt;
  const AppError({required this.id, required this.message, required this.screen, required this.kind, required this.appVersion, this.createdAt});

  factory AppError.fromDoc(String id, Map<String, dynamic> m) => AppError(
        id: id,
        message: (m['message'] ?? '') as String,
        screen: (m['screen'] ?? '') as String,
        kind: (m['kind'] ?? '') as String,
        appVersion: (m['appVersion'] ?? '') as String,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// `app_errors/{id}`: a sample of the errors the app hit, for the admin
/// health screen. Holds no personal data: no user id, and the message has
/// e-mail addresses, links and long numbers removed. Rules: any signed-in
/// user creates, super and ops admins read, nobody changes or deletes.
class ErrorLogService {
  ErrorLogService._();

  /// Share of errors that are written (the rest are only counted by Crashlytics).
  static double sampleRate = 0.25;

  /// At most this many writes per app run, and this far apart.
  static const maxPerSession = 10;
  static const minGap = Duration(seconds: 30);

  /// Off in debug builds (tests switch it on).
  static bool enabled = !kDebugMode;

  /// The newest cleaned error text of this app run (shown to support when a
  /// person reports a problem). Never holds personal data.
  static String? lastError;

  static int _written = 0;
  static DateTime? _last;
  static final _seen = <String>{};

  @visibleForTesting
  static void reset() {
    _written = 0;
    _last = null;
    _seen.clear();
    lastError = null;
    sampleRate = 0.25;
    enabled = !kDebugMode;
  }

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('app_errors');

  /// Error text without e-mail addresses, links or numbers of 6+ digits
  /// (phones, ids), collapsed to one line and at most [maxLength] characters.
  static String sanitize(String text, {int maxLength = 300}) {
    var t = text.replaceAll(RegExp(r'\S+@\S+'), ' ');
    t = t.replaceAll(RegExp(r'https?://\S+|www\.\S+', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'\d{6,}'), '#');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > maxLength ? t.substring(0, maxLength).trim() : t;
  }

  /// The app file the error came from, as `driver/driver_trip_screen.dart`
  /// (first `package:transport_app/` frame of [stack]), else 'unknown'.
  static String screenFromStack(StackTrace? stack) {
    final m = RegExp(r'package:transport_app/([\w/]+\.dart)').firstMatch(stack?.toString() ?? '');
    final file = m?.group(1) ?? 'unknown';
    return file.length > 60 ? file.substring(file.length - 60) : file;
  }

  /// Writes the error when it is sampled in, new this session, signed in and
  /// not too soon after the last one. Never throws. Returns true when written.
  static Future<bool> logSampled(Object error, StackTrace? stack, {bool fatal = false, Random? random, DateTime Function()? now}) async {
    final message = sanitize('$error');
    if (message.isNotEmpty) lastError = message;
    if (!enabled || Backend.uid == null) return false;
    if (_written >= maxPerSession) return false;
    if (message.isEmpty || _seen.contains(message)) return false;
    final at = (now ?? DateTime.now)();
    final last = _last;
    if (last != null && at.difference(last) < minGap) return false;
    if ((random ?? Random()).nextDouble() >= sampleRate) return false;
    _seen.add(message);
    _last = at;
    _written++;
    try {
      await _col.add({
        'message': message,
        'screen': screenFromStack(stack),
        'kind': fatal ? 'flutter' : 'async',
        'appVersion': appVersion.length > 20 ? appVersion.substring(0, 20) : appVersion,
        'createdAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 90))), // TTL policy, docs/DATA_RETENTION.md
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Newest [limit] for the admin screen.
  static Stream<List<AppError>> watchRecent({int limit = 20}) =>
      _col.orderBy('createdAt', descending: true).limit(limit).snapshots().map((s) => [for (final d in s.docs) AppError.fromDoc(d.id, d.data())]);
}
