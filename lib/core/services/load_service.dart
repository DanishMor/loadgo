import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../location/geohash.dart';

import '../constants/logistics.dart';
import '../models/load.dart';
import '../constants/prohibited_cargo.dart';
import '../matching/nearest.dart';
import '../models/paged.dart';
import '../enterprise/validators.dart';
import 'audit_service.dart';
import 'risk_service.dart';
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
    String paymentMode = 'cash',
    String containerNumber = '',
    String sealNumber = '',
    String? branchId,
    String? shipmentId,
    int? shipmentLeg,
    String bookingType = BookingType.freight,
    int helpers = 0,
    int? rentalHours,
    MoversDetails? movers,
  }) async {
    if (!BookingType.all.contains(bookingType)) throw ArgumentError.value(bookingType, 'bookingType');
    if (helpers < 0 || helpers > maxHelpers) throw ArgumentError.value(helpers, 'helpers');
    if (bookingType == BookingType.rental && !rentalHourOptions.contains(rentalHours)) {
      throw ArgumentError.value(rentalHours, 'rentalHours');
    }
    if (bookingType == BookingType.movers && (movers == null || movers.items.isEmpty)) {
      throw ArgumentError('A movers request needs at least one item');
    }
    final uid = Backend.requireUid();
    await RiskService.ensureCanTransact();
    final banned = prohibitedCargoMatch('$notes $cargoType');
    if (banned != null) throw ProhibitedCargoException(banned);
    List<String> clean(List<String> l) =>
        [for (final s in l) if (s.trim().isNotEmpty) s.trim()].take(maxStopsPerSide - 1).toList();
    final geohash = pickupGeohashFor(pickup);
    final ref = await _col.add({
      'pickupGeohash': ?geohash,
      'bookingType': bookingType,
      'helpers': helpers,
      if (bookingType == BookingType.rental) 'rentalHours': rentalHours,
      if (bookingType == BookingType.movers) 'movers': movers!.toMap(),
      if (clean(extraPickups).isNotEmpty) 'extraPickups': clean(extraPickups),
      if (clean(extraDrops).isNotEmpty) 'extraDrops': clean(extraDrops),
      'pickupSlot': pickupSlot,
      'paymentMode': paymentMode,
      if (containerNumber.trim().isNotEmpty) 'containerNumber': normaliseContainer(containerNumber),
      if (sealNumber.trim().isNotEmpty) 'sealNumber': sealNumber.trim(),
      'branchId': ?branchId,
      'shipmentId': ?shipmentId,
      'shipmentLeg': ?shipmentLeg,
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
        RiskService.countCancel(tx);
        AuditService.inTransaction(tx, AuditType.cancel, loadId: loadId, data: {'by': 'customer'});
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

  /// Open loads whose pickup city is in the driver's geohash cell or the
  /// cells around it, found with prefix range queries on `pickupGeohash`
  /// (no need to page through everything). Merged from up to 9 live queries;
  /// own loads are hidden. Sort the result by distance.
  static Stream<List<Load>> watchNearby(LatLng origin, {double radiusKm = 150}) {
    final uid = Backend.uid;
    final precision = geohashPrecisionForKm(radiusKm);
    final cells = geohashCells(origin.lat, origin.lng, precision);
    late StreamController<List<Load>> out;
    final latest = <String, List<Load>>{};
    final subs = <StreamSubscription>[];
    void emit() => out.add([for (final l in latest.values.expand((x) => x)) if (l.shipperId != uid) l]);

    out = StreamController<List<Load>>(
      onListen: () {
        for (final cell in cells) {
          subs.add(_col
              .where('status', isEqualTo: LoadStatus.open)
              .where('pickupGeohash', isGreaterThanOrEqualTo: cell)
              .where('pickupGeohash', isLessThan: '$cell~')
              .limit(50)
              .snapshots()
              .listen((snap) {
            latest[cell] = snap.docs.map(Load.fromDoc).toList();
            emit();
          }, onError: out.addError));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  /// Sets `pickupGeohash` on loads that were posted before the field existed
  /// (admin tool, see docs/MIGRATIONS.md). Returns how many were updated.
  static Future<int> backfillPickupGeohash({int limit = 400}) async {
    final snap = await _col.limit(limit).get();
    var n = 0;
    var batch = Backend.db.batch();
    for (final d in snap.docs) {
      if (d.data().containsKey('pickupGeohash')) continue;
      final g = pickupGeohashFor(d.data()['pickup'] as String? ?? '');
      if (g == null) continue;
      batch.update(d.reference, {'pickupGeohash': g});
      n++;
    }
    if (n > 0) await batch.commit();
    return n;
  }

  static List<Load> _sorted(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map(Load.fromDoc).toList();
    list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
    return list;
  }
}
