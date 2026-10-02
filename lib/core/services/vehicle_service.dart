import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/vehicle.dart';
import 'backend.dart';

class VehicleService {
  VehicleService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      Backend.db.collection('vehicles');

  /// Strips spaces/dashes and upper-cases, e.g. "mh 12-ab 1234" -> "MH12AB1234".
  static String normalizeNumber(String raw) =>
      raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  static bool isValidNumber(String raw) =>
      RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(normalizeNumber(raw));

  static Stream<List<Vehicle>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('ownerId', isEqualTo: uid).snapshots().map((snap) {
      final list = snap.docs.map(Vehicle.fromDoc).toList();
      list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
      return list;
    });
  }

  static Future<List<Vehicle>> fetchMyActive() async {
    final uid = Backend.requireUid();
    final snap = await _col.where('ownerId', isEqualTo: uid).get();
    return snap.docs.map(Vehicle.fromDoc).where((v) => v.isActive).toList();
  }

  static Future<String> add({
    required String number,
    required String type,
    required num capacity,
    required String rcNumber,
  }) async {
    final uid = Backend.requireUid();
    final ref = await _col.add({
      'ownerId': uid,
      'number': normalizeNumber(number),
      'type': type,
      'capacity': capacity,
      'rcNumber': rcNumber.trim().toUpperCase(),
      'status': VehicleStatus.active,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> setActive(String vehicleId, bool active) {
    return _col.doc(vehicleId).update({
      'status': active ? VehicleStatus.active : VehicleStatus.inactive,
    });
  }
}
