import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/load.dart';
import '../constants/prohibited_cargo.dart';
import '../models/paged.dart';
import '../pricing/fare_calculator.dart';
import 'backend.dart';

class LoadNotCancellableException implements Exception {
  @override
  String toString() => 'LoadNotCancellableException';
}

/// The load mentions goods LoadGo does not carry; [item] is the match.
class ProhibitedCargoException implements Exception {
  final String item;
  ProhibitedCargoException(this.item);

  @override
  String toString() => 'ProhibitedCargoException($item)';
}

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
    FareBreakdown? estimate,
    String? distanceSource,
    List<String> extraPickups = const [],
    List<String> extraDrops = const [],
    String pickupSlot = PickupSlot.any,
  }) async {
    final uid = Backend.requireUid();
    final banned = prohibitedCargoMatch('$notes $cargoType');
    if (banned != null) throw ProhibitedCargoException(banned);
    List<String> clean(List<String> l) =>
        [for (final s in l) if (s.trim().isNotEmpty) s.trim()].take(maxStopsPerSide - 1).toList();
    final ref = await _col.add({
      if (clean(extraPickups).isNotEmpty) 'extraPickups': clean(extraPickups),
      if (clean(extraDrops).isNotEmpty) 'extraDrops': clean(extraDrops),
      'pickupSlot': pickupSlot,
      if (estimate != null) 'estimate': {...estimate.toMap(), 'distanceSource': ?distanceSource},
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

  /// Cancels the shipper's own load while it is still open.
  ///
  /// Throws [LoadNotCancellableException] when a driver has already accepted
  /// it (the rules reject the write once the load is no longer open).
  static Future<void> cancel(String loadId) async {
    final ref = _col.doc(loadId);
    try {
      await Backend.db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final load = Load.fromDoc(snap);
        if (!snap.exists || load.shipperId != Backend.requireUid()) throw StateError('Not your load');
        if (!load.isOpen) throw LoadNotCancellableException();
        tx.update(ref, {
          'status': LoadStatus.closed,
          'cancelled': true,
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw LoadNotCancellableException();
      rethrow;
    }
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

  /// Paged "My Loads": the newest [limit] loads the customer posted.
  static Stream<Paged<Load>> watchMinePage(int limit) {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const Paged.all([]));
    return newestPage(_col.where('shipperId', isEqualTo: uid), limit)
        .map((snap) => Paged(_sorted(snap), hasMore: snap.docs.length >= limit));
  }

  /// Paged open loads for drivers (own loads hidden); [Paged.hasMore] reflects
  /// the server page, not the filtered list.
  static Stream<Paged<Load>> watchOpenPage(int limit) {
    final uid = Backend.uid;
    return newestPage(_col.where('status', isEqualTo: LoadStatus.open), limit).map((snap) => Paged(
          _sorted(snap).where((l) => l.shipperId != uid).toList(),
          hasMore: snap.docs.length >= limit,
        ));
  }

  static List<Load> _sorted(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map(Load.fromDoc).toList();
    list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
    return list;
  }
}
