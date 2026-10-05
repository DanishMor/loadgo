import 'package:cloud_firestore/cloud_firestore.dart';

import '../documents/doc_expiry.dart';
import '../models/vehicle.dart';
import 'backend.dart';

/// Puts the signed-in owner's vehicles into `doc_expired` while an insurance,
/// permit or fitness paper is expired, and back to `available` once renewed
/// (or an admin override is active). The rules refuse bookings with expired
/// papers anyway; this keeps the state visible. TODO(functions): run it on a
/// schedule instead of when the app opens.
class DocExpiryService {
  DocExpiryService._();

  /// Returns how many vehicles changed.
  static Future<int> syncMine({DateTime? now}) async {
    final uid = Backend.uid;
    if (uid == null) return 0;
    final t = now ?? DateTime.now();
    final snap = await Backend.db.collection('vehicles').where('ownerId', isEqualTo: uid).get();
    var changed = 0;
    for (final d in snap.docs) {
      if (await _apply(Vehicle.fromDoc(d), t)) changed++;
    }
    return changed;
  }

  /// Re-checks one vehicle (after its documents were saved).
  static Future<bool> syncVehicle(String vehicleId, {DateTime? now}) async {
    final d = await Backend.db.collection('vehicles').doc(vehicleId).get();
    if (!d.exists) return false;
    final v = Vehicle.fromDoc(d);
    if (v.ownerId != Backend.uid) return false;
    return _apply(v, now ?? DateTime.now());
  }

  static Future<bool> _apply(Vehicle v, DateTime now) async {
    final target = DocExpiry.vehicleTarget(v, now);
    if (target == null) return false;
    await Backend.db.collection('vehicles').doc(v.id).update({'availability': target, 'updatedAt': FieldValue.serverTimestamp()});
    return true;
  }
}
