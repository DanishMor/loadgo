import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../enterprise/validators.dart';
import '../identity/identity_index.dart';
import '../identity/kyc_validators.dart';
import 'backend.dart';
import 'push_service.dart';

/// The account is already locked to [existing]; [requested] was chosen at login.
class RoleMismatchException implements Exception {
  final String existing;
  final String requested;
  const RoleMismatchException({required this.existing, required this.requested});

  @override
  String toString() => 'RoleMismatchException(existing: $existing, requested: $requested)';
}

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

  /// Throws [RoleMismatchException] when the account is locked to another role.
  static void ensureRoleAllowed(String? lockedRole, String requested) {
    if (lockedRole != null && lockedRole != requested) {
      throw RoleMismatchException(existing: lockedRole, requested: requested);
    }
  }

  /// OTP verify hote hi call karo — role aur session record karta hai.
  /// `role` is set once and never changes (rules enforce it too); logging in
  /// through the other role's door throws [RoleMismatchException].
  static Future<void> markRoleSelected(String role) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();

    ensureRoleAllowed(snap.data()?['role'] as String?, role);

    final data = <String, dynamic>{
      'phone': user.phoneNumber,
      'role': role,
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
    String gstin = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = _db.collection('users').doc(user.uid);

    // GST is optional; when given it must not belong to another account.
    final gst = normaliseGstin(gstin);
    final claims = {if (gst.isNotEmpty) IdentityType.gst: gst};
    await IdentityIndex.assertAvailable(claims, uid: user.uid);

    final data = <String, dynamic>{
      'phone': user.phoneNumber,
      'name': name,
      'language': language,
      'profileComplete': true,
      'role': 'customer',
      'selectedRole': 'customer',
      'roles': FieldValue.arrayUnion(['customer']),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (companyName.isNotEmpty) data['companyName'] = companyName;
    if (email.isNotEmpty) data['email'] = email;
    // Format-checked only, never verified (see enterprise validators).
    if (gst.isNotEmpty) data['business'] = {'legalName': companyName, 'gstin': gst};

    final batch = _db.batch();
    batch.set(ref, data, SetOptions(merge: true));
    await IdentityIndex.addClaims(batch, claims, uid: user.uid, role: 'customer');
    await batch.commit();
  }

  /// Driver onboarding documents. Saved together with their identity index
  /// entries, so a document already used by another account is refused
  /// ([DuplicateIdentityException]) and nothing is written. Only the last four
  /// Aadhaar digits ever reach Firestore.
  static Future<void> saveDriverKyc(DriverKyc kyc) async {
    final uid = Backend.requireUid();
    final claims = {
      IdentityType.dl: kyc.dlNumber,
      IdentityType.pan: kyc.pan,
      IdentityType.rc: kyc.rcNumber,
    };
    await IdentityIndex.assertAvailable(claims, uid: uid);

    final batch = _db.batch();
    batch.set(
      _db.collection('users').doc(uid),
      {
        'driverKyc': kyc.toMap(),
        'kycComplete': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await IdentityIndex.addClaims(batch, claims, uid: uid, role: 'driver');
    await batch.commit();
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
      'role': 'driver',
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

  static Future<void> logout() async {
    await PushService.unregister();
    await FirebaseAuth.instance.signOut();
  }
}