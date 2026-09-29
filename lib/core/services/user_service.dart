import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  UserService._();

  static final _db = FirebaseFirestore.instance;

  static Future<Map<String, dynamic>?> getUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final snap = await _db.collection('users').doc(user.uid).get();
    return snap.data();
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

  static Future<void> logout() => FirebaseAuth.instance.signOut();
}