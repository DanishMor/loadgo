import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

/// Persists the chosen app language on the device and, when signed in, on
/// the user's profile (`users/{uid}.language`, the enum name).
class LanguageStore {
  LanguageStore._();

  static const _key = 'app_language';

  /// Language saved on this device, or null.
  static Future<String?> loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, name);
    } catch (_) {}
    final uid = Backend.uid;
    if (uid == null) return;
    try {
      await Backend.db.collection('users').doc(uid).set(
        {'language': name, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {
      // Offline or no profile yet; the device copy is enough until next save.
    }
  }

  /// Language stored on the signed-in user's profile, or null.
  static Future<String?> loadRemote() async {
    final uid = Backend.uid;
    if (uid == null) return null;
    try {
      final snap = await Backend.db.collection('users').doc(uid).get();
      return snap.data()?['language'] as String?;
    } catch (_) {
      return null;
    }
  }
}
