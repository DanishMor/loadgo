import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../location/geohash.dart';

import '../constants/logistics.dart';
import '../models/load.dart';
import '../constants/prohibited_cargo.dart';
import '../matching/nearest.dart';
import '../risk/risk_rules.dart';
import '../scheduling/schedule.dart';
import 'pricing_service.dart';
import '../models/paged.dart';
import '../enterprise/validators.dart';
import '../offers/promo.dart';
import 'audit_service.dart';
import 'rewards_service.dart';
import 'risk_service.dart';
import '../pricing/fare_calculator.dart';
import 'backend.dart';
import 'business_ops_service.dart';
import 'repeat_service.dart';
import 'rate_limit_service.dart';

/// The chosen pickup time breaks the advance-booking limits.
class ScheduleException implements Exception {
  final ScheduleProblem problem;
  const ScheduleException(this.problem);

  @override
  String toString() => 'ScheduleException($problem)';
}

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
    PromoApplication? promo,
    int creditsUsedPaise = 0,
    bool fragile = false,
    bool highValue = false,
    DateTime? scheduledAt,
    String? invitedDriverId,
    String? businessId,
    String? costCenter,
    String visibility = LoadVisibility.public,
    List<String> allowedDriverIds = const [],
    bool instant = false,
  }) async {
    if (scheduledAt != null) {
      final problem = Schedule.check(scheduledAt, DateTime.now(), PricingService.config.schedule);
      if (problem != null) throw ScheduleException(problem);
    }
    if (creditsUsedPaise < 0) throw ArgumentError.value(creditsUsedPaise, 'creditsUsedPaise');
    if (!BookingType.all.contains(bookingType)) throw ArgumentError.value(bookingType, 'bookingType');
    if (helpers < 0 || helpers > maxHelpers) throw ArgumentError.value(helpers, 'helpers');
    if (bookingType == BookingType.rental && !rentalHourOptions.contains(rentalHours)) {
      throw ArgumentError.value(rentalHours, 'rentalHours');
    }
    if (bookingType == BookingType.movers && (movers == null || movers.items.isEmpty)) {
      throw ArgumentError('A movers request needs at least one item');
    }
    if (!LoadVisibility.all.contains(visibility)) throw ArgumentError.value(visibility, 'visibility');
    if (visibility != LoadVisibility.public && (allowedDriverIds.isEmpty || allowedDriverIds.length > LoadVisibility.maxAllowed)) {
      throw ArgumentError.value(allowedDriverIds, 'allowedDriverIds');
    }
    if (costCenter != null && costCenter.trim().length > 30) throw ArgumentError.value(costCenter, 'costCenter');
    final uid = Backend.requireUid();
    await RiskService.ensureCanTransact();
    final banned = prohibitedCargoMatch('$notes $cargoType');
    if (banned != null) throw ProhibitedCargoException(banned);
    List<String> clean(List<String> l) =>
        [for (final s in l) if (s.trim().isNotEmpty) s.trim()].take(maxStopsPerSide - 1).toList();
    final geohash = pickupGeohashFor(pickup);
    final blocked = await RepeatService.blockedIds(uid);
    // BIZ6: a team member's load over the company's approval limit waits for the owner or a manager.
    final awaiting = businessId != null && businessId != uid && await BusinessOpsService.approvalNeeded(businessId, budget == null ? (estimate?.total ?? 0) : (budget * 100).round());
    final ref = _col.doc();
    final rate = await RateLimit.prepare(RateLimit.loadKind, docId: ref.id);
    final data = <String, Object?>{
      if (blocked.isNotEmpty) 'blockedDriverIds': blocked,
      if (visibility != LoadVisibility.public) 'visibility': visibility,
      if (visibility != LoadVisibility.public) 'allowedDriverIds': allowedDriverIds,
      if (instant) 'instant': true,
      'pickupGeohash': ?geohash,
      'bookingType': bookingType,
      'invitedDriverId': ?invitedDriverId,
      'businessId': ?businessId,
      if (costCenter != null && costCenter.trim().isNotEmpty) 'costCenter': costCenter.trim(),
      if (scheduledAt != null) 'scheduledAt': Timestamp.fromDate(scheduledAt),
      if (fragile) 'fragile': true,
      if (highValue) 'highValue': true,
      'helpers': helpers,
      if (bookingType == BookingType.rental) 'rentalHours': rentalHours,
      if (bookingType == BookingType.movers) 'movers': movers!.toMap(),
      if (clean(extraPickups).isNotEmpty) 'extraPickups': clean(extraPickups),
      if (clean(extraDrops).isNotEmpty) 'extraDrops': clean(extraDrops),
      'pickupSlot': scheduledAt == null ? pickupSlot : Schedule.slotFor(scheduledAt),
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
      'pickupDate': Timestamp.fromDate(DateTime((scheduledAt ?? pickupDate).year, (scheduledAt ?? pickupDate).month, (scheduledAt ?? pickupDate).day)),
      'notes': notes.trim(),
      'status': awaiting ? LoadStatus.awaitingApproval : LoadStatus.open,
      'createdAt': FieldValue.serverTimestamp(),
      if (promo != null) 'promo': promo.toLoadMap(),
      if (creditsUsedPaise > 0) 'creditsUsedPaise': creditsUsedPaise,
    };
    final batch = Backend.db.batch();
    batch.set(ref, data);
    rate.addToBatch(batch);
    // Offers are recorded in the same batch: the promo slot and per-user use
    // documents, and the credits spend line (the rules check all of them).
    if (promo != null) RewardsService.addRedemption(batch, promo, loadId: ref.id, uid: uid);
    if (creditsUsedPaise > 0) RewardsService.addSpend(batch, uid: uid, loadId: ref.id, paise: creditsUsedPaise);
    // High-value load: tell admins (a signal, not a block).
    if (estimate != null && RiskRules.isHighValue(estimate.total)) {
      batch.set(Backend.db.collection('risk_signals').doc(), {
        'uid': uid,
        'type': 'high_value',
        'amountPaise': estimate.total,
        'note': 'load ${ref.id}',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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
        .map((snap) => _sorted(snap).where((l) => l.shipperId != uid && !l.blocks(uid)).toList());
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
          _sorted(snap).where((l) => l.shipperId != uid && !l.blocks(uid)).toList(),
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
    void emit() => out.add([for (final l in latest.values.expand((x) => x)) if (l.shipperId != uid && !l.blocks(uid)) l]);

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
