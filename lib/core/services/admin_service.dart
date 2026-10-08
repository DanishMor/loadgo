import 'package:cloud_firestore/cloud_firestore.dart';

import 'audit_service.dart';
import 'backend.dart';

/// A driver awaiting (or past) verification, as shown to admins.
class DriverVerification {
  final String uid;
  final String name;
  final String phone;
  final String vehicleNumber;
  final String vehicleType;
  final String status;

  /// The whole profile, so the admin can see the documents behind the request.
  final Map<String, dynamic> data;

  const DriverVerification({
    required this.uid,
    required this.name,
    required this.phone,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.status,
    this.data = const {},
  });

  /// A transporter waiting for (or holding) the "Verified transporter" badge.
  bool get isTransporter => data['role'] == 'fleet';

  factory DriverVerification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DriverVerification(
      uid: doc.id,
      name: d['driverName'] as String? ?? (d['role'] == 'fleet' ? (d['companyName'] as String? ?? d['name'] as String? ?? '') : ''),
      phone: d['phone'] as String? ?? '',
      vehicleNumber: d['vehicleNumber'] as String? ?? '',
      vehicleType: d['vehicleType'] as String? ?? '',
      status: d['verificationStatus'] as String? ?? 'pending',
      data: d,
    );
  }
}

/// Driver verification for admins. Firestore rules only allow this for users
/// listed in `admins/{uid}`.
class AdminService {
  AdminService._();

  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';

  /// Live drivers whose verification status is [status].
  static Stream<List<DriverVerification>> watchDrivers(String status) {
    return Backend.db
        .collection('users')
        .where('verificationStatus', isEqualTo: status)
        .snapshots()
        .map((s) => s.docs.map(DriverVerification.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name)));
  }

  static Future<void> setStatus(String uid, String status) {
    assert(const [pending, approved, rejected].contains(status));
    final batch = Backend.db.batch();
    batch.update(Backend.db.collection('users').doc(uid), {
      'verificationStatus': status,
      'verified': status == approved,
      // Who decided, how and when (no external source yet: LATER(paid) KYC APIs).
      'verificationMeta': {
        'source': 'manual_review',
        'by': Backend.requireUid(),
        'status': status,
        'at': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.verification, targetId: uid, data: {'status': status});
    return batch.commit();
  }
}
