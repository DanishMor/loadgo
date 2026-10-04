import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user_settings.dart';
import 'backend.dart';

/// Notification preferences, consents and the delete-account request.
class SettingsService {
  SettingsService._();

  /// Preferences of the signed-in user, used to filter in-app notifications.
  static final ValueNotifier<NotificationPrefs> prefs = ValueNotifier(const NotificationPrefs());

  static DocumentReference<Map<String, dynamic>> get _user => Backend.db.collection('users').doc(Backend.requireUid());

  static Future<Map<String, dynamic>> _profile() async => (await _user.get()).data() ?? const {};

  static Future<void> refresh() async {
    try {
      prefs.value = NotificationPrefs.fromMap((await _profile())['notificationPrefs']);
    } catch (_) {
      // Signed out / offline: keep what we have.
    }
  }

  static Future<NotificationPrefs> loadPrefs() async {
    final p = NotificationPrefs.fromMap((await _profile())['notificationPrefs']);
    prefs.value = p;
    return p;
  }

  static Future<void> savePrefs(NotificationPrefs p) async {
    await _user.set({'notificationPrefs': p.toMap(), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    prefs.value = p;
  }

  static Future<Consents> loadConsents() async => Consents.fromMap((await _profile())['consents']);

  static Future<void> saveConsents(Consents c) => _user.set(
        {'consents': c.toMap(), 'consentsUpdatedAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

  // ---- delete-account request ----
  // The account is not deleted by the app: an admin reviews the request and
  // removes the data (TODO(functions): automate with the Admin SDK).

  static DocumentReference<Map<String, dynamic>> get _deletion => Backend.db.collection('deletion_requests').doc(Backend.requireUid());

  static Future<bool> hasPendingDeletion() async {
    final d = (await _deletion.get()).data();
    return d != null && d['status'] == 'pending';
  }

  static Future<void> requestDeletion({String reason = ''}) => _deletion.set({
        'userId': Backend.requireUid(),
        'status': 'pending',
        'reason': reason.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
}
