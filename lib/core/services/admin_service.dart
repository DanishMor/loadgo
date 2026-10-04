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

  const DriverVerification({
    required this.uid,
    required this.name,
    required this.phone,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.status,
  });

  factory DriverVerification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DriverVerification(
      uid: doc.id,
      name: d['driverName'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      vehicleNumber: d['vehicleNumber'] as String? ?? '',
      vehicleType: d['vehicleType'] as String? ?? '',
      status: d['verificationStatus'] as String? ?? 'pending',
    );
  }
}

/// Driver verification for admins. Firestore rules only allow this for users
/// with the `admin` custom claim; the app does not check that itself yet.
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
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.verification, targetId: uid, data: {'status': status});
    return batch.commit();
  }
}
