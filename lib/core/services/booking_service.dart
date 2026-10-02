import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/load.dart';
import '../models/vehicle.dart';
import 'backend.dart';

/// Thrown when a load was taken by another driver, closed, or never existed.
class LoadUnavailableException implements Exception {
  @override
  String toString() => 'LoadUnavailableException';
}

class BookingService {
  BookingService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      Backend.db.collection('bookings');

  /// Atomically books an open load for the signed-in driver.
  ///
  /// The booking id equals the load id, so a load can only ever have one
  /// booking. Returns the booking id.
  static Future<String> accept({required String loadId, required Vehicle vehicle}) async {
    final uid = Backend.requireUid();
    final profile = (await Backend.db.collection('users').doc(uid).get()).data() ?? const {};
    final loadRef = Backend.db.collection('loads').doc(loadId);
    final bookingRef = _col.doc(loadId);

    try {
      await Backend.db.runTransaction((tx) async {
        final snap = await tx.get(loadRef);
        if (!snap.exists) throw LoadUnavailableException();
        final load = Load.fromDoc(snap);
        if (!load.isOpen || load.shipperId == uid) throw LoadUnavailableException();

        tx.set(bookingRef, {
          'loadId': load.id,
          'driverId': uid,
          'vehicleId': vehicle.id,
          'customerId': load.shipperId,
          'status': BookingStatus.accepted,
          'pickup': load.pickup,
          'drop': load.drop,
          'cargoType': load.cargoType,
          'weight': load.weight,
          'vehicleType': load.vehicleType,
          'budget': load.budget,
          'pickupDate': snap.data()!['pickupDate'],
          'notes': load.notes,
          'vehicleNumber': vehicle.number,
          'driverName': profile['driverName'] ?? '',
          'driverPhone': profile['phone'] ?? '',
          'timeline': {BookingStatus.accepted: FieldValue.serverTimestamp()},
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(loadRef, {
          'status': LoadStatus.matched,
          'driverId': uid,
          'bookingId': bookingRef.id,
          'matchedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (e) {
      // Rules hide loads matched by other drivers, so a lost race surfaces as
      // permission-denied (or aborted under contention).
      if (e.code == 'permission-denied' || e.code == 'aborted' || e.code == 'not-found') {
        throw LoadUnavailableException();
      }
      rethrow;
    }
    return bookingRef.id;
  }

  static Stream<List<Booking>> watchForDriver() => _watchWhere('driverId');

  static Stream<List<Booking>> watchForCustomer() => _watchWhere('customerId');

  static Stream<List<Booking>> _watchWhere(String field) {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where(field, isEqualTo: uid).snapshots().map((snap) {
      final list = snap.docs.map(Booking.fromDoc).toList();
      list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
      return list;
    });
  }
}
