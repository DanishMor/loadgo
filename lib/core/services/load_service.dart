import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/load.dart';
import 'backend.dart';

class LoadService {
  LoadService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      Backend.db.collection('loads');

  static Future<String> post({
    required String pickup,
    required String drop,
    required String cargoType,
    required num weight,
    required String vehicleType,
    required num? budget,
    required DateTime pickupDate,
    required String notes,
  }) async {
    final uid = Backend.requireUid();
    final ref = await _col.add({
      'shipperId': uid,
      'pickup': pickup.trim(),
      'drop': drop.trim(),
      'cargoType': cargoType,
      'weight': weight,
      'vehicleType': vehicleType,
      'budget': budget,
      'pickupDate': Timestamp.fromDate(DateTime(pickupDate.year, pickupDate.month, pickupDate.day)),
      'notes': notes.trim(),
      'status': LoadStatus.open,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Loads posted by the signed-in customer, newest first.
  static Stream<List<Load>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('shipperId', isEqualTo: uid).snapshots().map(_sorted);
  }

  /// Open loads for drivers, excluding loads the signed-in user posted.
  static Stream<List<Load>> watchOpen() {
    final uid = Backend.uid;
    return _col
        .where('status', isEqualTo: LoadStatus.open)
        .snapshots()
        .map((snap) => _sorted(snap).where((l) => l.shipperId != uid).toList());
  }

  static List<Load> _sorted(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map(Load.fromDoc).toList();
    list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
    return list;
  }
}
