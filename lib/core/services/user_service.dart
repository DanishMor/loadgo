import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'backend.dart';

class UserService {
  UserService._();

  static FirebaseFirestore get _db => Backend.db;

  static Future<Map<String, dynamic>?> getUser() async {
    final uid = Backend.uid;
    if (uid == null) return null;
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data();
  }

  /// Live profile of the signed-in user (empty map if not created yet).
  static Stream<Map<String, dynamic>> watchUser() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const {});
    return _db.collection('users').doc(uid).snapshots().map((s) => s.data() ?? const {});
  }

  /// OTP verify hote hi call karo — role aur session record karta hai.
  static Future<void> markRoleSelected(String role) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();

    final data = <String, dynamic>{
      'phone': user.phoneNumber,
      'selectedRole': role,
      'roles': FieldValue.arrayUnion([role]),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!snap.exists) data['createdAt'] = FieldValue.serverTimestamp();

    await ref.set(data, SetOptions(merge: true));
  }

  static Future<void> saveCustomerProfile({
    required String name,
    required String companyName,
    required String email,
    required String language,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = _db.collection('users').doc(user.uid);

    final data = <String, dynamic>{
      'phone': user.phoneNumber,
      'name': name,
      'language': language,
      'profileComplete': true,
      'selectedRole': 'customer',
      'roles': FieldValue.arrayUnion(['customer']),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (companyName.isNotEmpty) data['companyName'] = companyName;
    if (email.isNotEmpty) data['email'] = email;

    await ref.set(data, SetOptions(merge: true));
  }

  static Future<void> saveDriverProfile({
    required String name,
    required String vehicleNumber,
    required String vehicleType,
    required String language,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    final existing = snap.data();

    final data = <String, dynamic>{
      'phone': user.phoneNumber,
      'driverName': name,
      'vehicleNumber': vehicleNumber,
      'vehicleType': vehicleType,
      'language': language,
      'driverProfileComplete': true,
      'selectedRole': 'driver',
      'roles': FieldValue.arrayUnion(['driver']),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // Admin ka pichla verification decision overwrite mat karo.
    if (existing == null || existing['verificationStatus'] == null) {
      data['verificationStatus'] = 'pending';
      data['verified'] = false;
    }

    await ref.set(data, SetOptions(merge: true));
  }

  /// Edits the signed-in user's profile after setup. Drivers keep their
  /// name in `driverName`, customers in `name`; blank optional fields are
  /// removed.
  static Future<void> updateProfile({
    required bool isDriver,
    required String name,
    required String email,
    required String companyName,
  }) async {
    final uid = Backend.requireUid();
    String? clean(String v) => v.trim().isEmpty ? null : v.trim();
    await _db.collection('users').doc(uid).update({
      isDriver ? 'driverName' : 'name': name.trim(),
      'email': clean(email) ?? FieldValue.delete(),
      'companyName': clean(companyName) ?? FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> logout() => FirebaseAuth.instance.signOut();
}