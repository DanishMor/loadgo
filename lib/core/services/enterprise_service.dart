import 'package:cloud_firestore/cloud_firestore.dart';

import '../enterprise/bulk_loads.dart';
import '../enterprise/route_report.dart';
import '../enterprise/shipment_timeline.dart';
import '../enterprise/validators.dart';
import '../models/booking.dart';
import '../models/enterprise.dart';
import '../models/load.dart';
import 'backend.dart';
import 'load_service.dart';

class InvalidTradeFieldException implements Exception {
  final String field;
  InvalidTradeFieldException(this.field);

  @override
  String toString() => 'InvalidTradeFieldException($field)';
}

/// Both legs of a shipment with their bookings (if any driver took them).
class ShipmentLegs {
  final Shipment shipment;
  final Load? leg1;
  final Booking? booking1;
  final Load? leg2;
  final Booking? booking2;

  const ShipmentLegs(this.shipment, this.leg1, this.booking1, this.leg2, this.booking2);

  LegStage get stage1 => legStage(leg1, booking1);
  LegStage get stage2 => legStage(leg2, booking2);
  List<TimelineStep> get timeline => shipmentTimeline(stage1, stage2);
  bool get complete => shipmentComplete(stage1, stage2);
}

/// Business profile, branches, bulk posting, two-leg shipments and the
/// route/branch report. All free-stack Firestore; GSTIN is format-checked
/// only (LATER(paid): verify with the GST portal).
class EnterpriseService {
  EnterpriseService._();

  static DocumentReference<Map<String, dynamic>> get _user => Backend.db.collection('users').doc(Backend.requireUid());

  // ---- business profile ----

  static Future<BusinessProfile> loadBusiness() async => BusinessProfile.fromMap((await _user.get()).data()?['business']);

  static Future<void> saveBusiness(BusinessProfile b) async {
    final clean = BusinessProfile(legalName: b.legalName.trim(), gstin: normaliseGstin(b.gstin), address: b.address.trim());
    if (!clean.gstinOk) throw InvalidTradeFieldException('gstin');
    await _user.set({'business': clean.toMap(), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  // ---- branches ----

  static CollectionReference<Map<String, dynamic>> get _branches => _user.collection('branches');

  static Stream<List<Branch>> watchBranches() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return Backend.db.collection('users').doc(uid).collection('branches').snapshots().map((s) {
      final list = s.docs.map(Branch.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  /// False when the 20-branch limit is reached.
  static Future<bool> addBranch({required String type, required String name, String address = '', String city = ''}) async {
    if (!BranchType.all.contains(type) || name.trim().isEmpty) throw ArgumentError('Branch needs a type and a name');
    if ((await _branches.get()).docs.length >= Branch.maxBranches) return false;
    await _branches.add({
      'type': type,
      'name': name.trim(),
      'address': address.trim(),
      'city': city.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  static Future<void> removeBranch(String id) => _branches.doc(id).delete();

  // ---- bulk post ----

  /// Posts every row (max [maxBulkLoads]) as its own open load for [pickupDate].
  /// Returns the new load ids; stops at the first failure and rethrows after
  /// recording how many succeeded in [BulkPostException].
  static Future<List<String>> postBulk(List<BulkLoadRow> rows, {required DateTime pickupDate}) async {
    if (rows.length > maxBulkLoads) throw ArgumentError('At most $maxBulkLoads loads');
    final ids = <String>[];
    for (final r in rows) {
      try {
        ids.add(await LoadService.post(
          pickup: r.pickup,
          drop: r.drop,
          cargoType: r.cargoType,
          weight: r.weight,
          vehicleType: r.vehicleType,
          budget: r.budget,
          pickupDate: pickupDate,
          notes: '',
        ));
      } catch (e) {
        throw BulkPostException(ids, e);
      }
    }
    return ids;
  }

  // ---- two-leg shipments ----

  static CollectionReference<Map<String, dynamic>> get _shipments => Backend.db.collection('shipments');

  /// Posts leg 1 (origin -> hub) and leg 2 (hub -> destination) as two loads
  /// linked by a shipment record. Container/seal numbers go on both legs.
  static Future<String> createTwoLeg({
    required String kind,
    required String origin,
    required String hub,
    required String destination,
    required String cargoType,
    required num weight,
    required String vehicleType,
    required DateTime leg1Date,
    required DateTime leg2Date,
    String containerNumber = '',
    String sealNumber = '',
    String? branchId,
  }) async {
    final container = normaliseContainer(containerNumber);
    if (container.isNotEmpty && !isValidContainerNumber(container)) throw InvalidTradeFieldException('container');
    if (sealNumber.trim().isNotEmpty && !isValidSealNumber(sealNumber)) throw InvalidTradeFieldException('seal');
    final ref = _shipments.doc();
    Future<String> leg(String from, String to, DateTime date, int n) => LoadService.post(
          pickup: from,
          drop: to,
          cargoType: cargoType,
          weight: weight,
          vehicleType: vehicleType,
          budget: null,
          pickupDate: date,
          notes: '',
          containerNumber: container,
          sealNumber: sealNumber,
          branchId: n == 1 ? branchId : null,
          shipmentId: ref.id,
          shipmentLeg: n,
        );
    final leg1 = await leg(origin, hub, leg1Date, 1);
    final leg2 = await leg(hub, destination, leg2Date, 2);
    await ref.set({
      'ownerId': Backend.requireUid(),
      'kind': kind,
      'origin': origin.trim(),
      'hub': hub.trim(),
      'destination': destination.trim(),
      'containerNumber': container,
      'sealNumber': sealNumber.trim(),
      'leg1LoadId': leg1,
      'leg2LoadId': leg2,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Stream<List<Shipment>> watchShipments() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _shipments.where('ownerId', isEqualTo: uid).snapshots().map((s) {
      final list = s.docs.map(Shipment.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
      return list;
    });
  }

  static Future<ShipmentLegs> legsOf(Shipment s) async {
    Future<(Load?, Booking?)> one(String loadId) async {
      if (loadId.isEmpty) return (null, null);
      final loadSnap = await Backend.db.collection('loads').doc(loadId).get();
      if (!loadSnap.exists) return (null, null);
      final load = Load.fromDoc(loadSnap);
      final bookingId = load.bookingId;
      if (bookingId == null) return (load, null);
      final b = await Backend.db.collection('bookings').doc(bookingId).get();
      return (load, b.exists ? Booking.fromDoc(b) : null);
    }

    final a = await one(s.leg1LoadId), b = await one(s.leg2LoadId);
    return ShipmentLegs(s, a.$1, a.$2, b.$1, b.$2);
  }

  // ---- report ----

  static Future<RouteReport> routeReport() async {
    final uid = Backend.requireUid();
    final db = Backend.db;
    final results = await Future.wait([
      db.collection('loads').where('shipperId', isEqualTo: uid).limit(500).get(),
      db.collection('bookings').where('customerId', isEqualTo: uid).limit(500).get(),
      _branches.get(),
    ]);
    return RouteReport.from(
      results[0].docs.map(Load.fromDoc),
      results[1].docs.map(Booking.fromDoc),
      results[2].docs.map(Branch.fromDoc),
    );
  }
}

/// A bulk post stopped part-way; [postedIds] were already created.
class BulkPostException implements Exception {
  final List<String> postedIds;
  final Object cause;
  BulkPostException(this.postedIds, this.cause);

  @override
  String toString() => 'BulkPostException(${postedIds.length} posted, $cause)';
}
