import 'package:cloud_firestore/cloud_firestore.dart';

import '../transporter/transporter_logic.dart';
import '../enterprise/validators.dart';
import '../identity/identity_index.dart';
import '../location/geohash.dart';
import '../identity/kyc_validators.dart';
import '../identity/profile_extras.dart';
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
    final user = Backend.currentUser;
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
    final user = Backend.currentUser;
    if (user == null) return;
    final ref = _db.collection('users').doc(user.uid);

    // GST is optional; when given it must not belong to another account.
    final gst = normaliseGstin(gstin);
    final before = (await ref.get()).data();

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
    final hashes = await IdentityIndex.applyChanges(
      batch,
      uid: user.uid,
      role: 'customer',
      oldNumbers: {IdentityType.gst: (before?['business'] as Map?)?['gstin'] as String?},
      newNumbers: {IdentityType.gst: gst},
    );
    data['identityHashes'] = hashes;
    batch.set(ref, data, SetOptions(merge: true));
    await batch.commit();
  }

  /// Transporter profile: name, company and PAN (unique across accounts),
  /// optional GSTIN. Saved with their identity index entries.
  static Future<void> saveFleetProfile({
    required String name,
    required String companyName,
    required String pan,
    String gstin = '',
    required String language,
    String officeCity = '',
    List<String> routes = const [],
    List<String> vehicleTypes = const [],
    int vehicleCount = 0,
  }) async {
    final user = Backend.currentUser;
    if (user == null) return;
    final ref = _db.collection('users').doc(user.uid);
    final before = (await ref.get()).data();
    final cleanPan = normaliseDocNumber(pan);
    if (!isValidPan(cleanPan)) throw ArgumentError.value(pan, 'pan');
    final gst = normaliseGstin(gstin);
    final batch = _db.batch();
    final hashes = await IdentityIndex.applyChanges(
      batch,
      uid: user.uid,
      role: 'fleet',
      oldNumbers: {
        IdentityType.pan: (before?['fleet'] as Map?)?['pan'] as String?,
        IdentityType.gst: (before?['business'] as Map?)?['gstin'] as String?,
      },
      newNumbers: {IdentityType.pan: cleanPan, IdentityType.gst: gst},
    );
    batch.set(
      ref,
      {
        'phone': user.phoneNumber,
        'name': name,
        'companyName': companyName,
        'language': language,
        'role': 'fleet',
        'selectedRole': 'fleet',
        'roles': FieldValue.arrayUnion(['fleet']),
        'fleet': TransporterProfile(pan: cleanPan, officeCity: officeCity, routes: routes, vehicleTypes: vehicleTypes, vehicleCount: vehicleCount).toFleetMap(),
        if (gst.isNotEmpty) 'business': {'legalName': companyName, 'gstin': gst},
        'identityHashes': hashes,
        'fleetProfileComplete': true,
        // The admin's earlier decision is never overwritten; a new account waits for review.
        if (before == null || before['verificationStatus'] == null) ...{'verificationStatus': 'pending', 'verified': false},
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Driver onboarding documents (also used to edit them later). Saved
  /// together with their identity index entries, so a document already used
  /// by another account is refused ([DuplicateIdentityException]) and nothing
  /// is written. Only the last four
  /// Aadhaar digits ever reach Firestore.
  static Future<void> saveDriverKyc(DriverKyc kyc) async {
    final uid = Backend.requireUid();
    final ref = _db.collection('users').doc(uid);
    final before = ((await ref.get()).data()?['driverKyc'] as Map?) ?? const {};

    // First save and later edits go the same way: the new numbers are
    // claimed and the ones they replace are released in one batch.
    final batch = _db.batch();
    final hashes = await IdentityIndex.applyChanges(
      batch,
      uid: uid,
      role: 'driver',
      oldNumbers: {
        IdentityType.dl: before['dlNumber'] as String?,
        IdentityType.pan: before['pan'] as String?,
        IdentityType.rc: before['rcNumber'] as String?,
      },
      newNumbers: {
        IdentityType.dl: kyc.dlNumber,
        IdentityType.pan: kyc.pan,
        IdentityType.rc: kyc.rcNumber,
      },
    );
    batch.set(
      ref,
      {
        'driverKyc': kyc.toMap(),
        'kycComplete': true,
        'identityHashes': hashes,
        if (before.isNotEmpty) 'kycEditedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  static Future<void> saveDriverProfile({
    required String name,
    required String vehicleNumber,
    required String vehicleType,
    required String language,
  }) async {
    final user = Backend.currentUser;
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

  /// Driver online / offline switch, kept on the profile so it survives a
  /// restart (and an admin can see who is available).
  static Future<void> setOnline(bool online) async {
    final uid = Backend.requireUid();
    await _db.collection('users').doc(uid).set({
      'online': online,
      'onlineChangedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Remembers where the driver last was (with a geohash) so loads can be
  /// listed nearest-first. LATER(paid): a Cloud Function reads the geohash
  /// for wave dispatch and FCM.
  static Future<void> saveDriverLocation(double lat, double lng) async {
    final uid = Backend.requireUid();
    await _db.collection('users').doc(uid).set({
      'lastLocation': {
        'lat': lat,
        'lng': lng,
        'geohash': geohashEncode(lat, lng),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  /// Last saved driver position, or null if none yet.
  static ({double lat, double lng})? lastLocationOf(Map<String, dynamic>? user) {
    final m = user?['lastLocation'];
    if (m is! Map) return null;
    final lat = m['lat'], lng = m['lng'];
    return lat is num && lng is num ? (lat: lat.toDouble(), lng: lng.toDouble()) : null;
  }

  /// Edits the signed-in user's profile after setup. Drivers keep their
  /// name in `driverName`, customers in `name`; blank optional fields are
  /// removed.
  static Future<void> updateProfile({
    required bool isDriver,
    required String name,
    required String email,
    required String companyName,
    String? currentAddress,
    String? permanentAddress,
    String? businessType,
    String? upiId,
    String? holder,
  }) async {
    final uid = Backend.requireUid();
    String? clean(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();
    final addr = {'current': ?clean(currentAddress), 'permanent': ?clean(permanentAddress)};
    final upi = clean(upiId);
    if (upi != null && !isValidUpiId(upi)) throw ArgumentError.value(upi, 'upiId');
    final pay = {'upiId': ?upi, 'holder': ?clean(holder)};
    await _db.collection('users').doc(uid).update({
      isDriver ? 'driverName' : 'name': name.trim(),
      'email': clean(email) ?? FieldValue.delete(),
      'companyName': clean(companyName) ?? FieldValue.delete(),
      // null = leave as it is (callers that do not show the field)
      if (currentAddress != null || permanentAddress != null) 'addresses': addr.isEmpty ? FieldValue.delete() : addr,
      if (businessType != null) 'businessType': BusinessType.all.contains(businessType) ? businessType : FieldValue.delete(),
      if (upiId != null || holder != null) 'payoutProfile': pay.isEmpty ? FieldValue.delete() : pay,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> logout() async {
    await PushService.unregister();
    await Backend.auth.signOut();
  }
}