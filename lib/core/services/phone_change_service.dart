import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'backend.dart';

/// Changing the login mobile number (R3). The new number is verified with an
/// SMS code (Firebase re-authenticates the session), then the profile phone is
/// updated and a `phone_change` risk signal is written for admins.
class PhoneChangeService {
  PhoneChangeService._();

  /// +91 and 10 digits starting 6-9, or null.
  static String? normalise(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    return RegExp(r'^[6-9][0-9]{9}$').hasMatch(d) ? '+91$d' : null;
  }

  /// Applies the verified [credential] and records the change.
  static Future<void> complete(PhoneAuthCredential credential, {required String newPhone}) async {
    final user = Backend.currentUser;
    if (user == null) throw StateError('not signed in');
    final old = user.phoneNumber ?? '';
    await user.updatePhoneNumber(credential);
    await record(oldPhone: old, newPhone: newPhone);
  }

  /// Profile phone + risk signal in one batch (also used by tests).
  static Future<void> record({required String oldPhone, required String newPhone}) async {
    final uid = Backend.requireUid();
    final db = Backend.db;
    final batch = db.batch();
    batch.set(db.collection('users').doc(uid), {'phone': newPhone, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    batch.set(db.collection('risk_signals').doc(), {
      'uid': uid,
      'type': 'phone_change',
      'note': 'from ${_tail(oldPhone)} to ${_tail(newPhone)}',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static String _tail(String p) => p.length <= 4 ? p : '•••${p.substring(p.length - 4)}';
}
