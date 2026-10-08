import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../constants/logistics.dart';
import '../models/vehicle.dart';
import 'backend.dart';
import 'doc_expiry_service.dart';

/// Another account (or another of your vehicles) already registered this number.
class DuplicateVehicleException implements Exception {
  @override
  String toString() => 'DuplicateVehicleException';
}

class VehicleService {
  VehicleService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      Backend.db.collection('vehicles');

  /// Strips spaces/dashes and upper-cases, e.g. "mh 12-ab 1234" -> "MH12AB1234".
  static String normalizeNumber(String raw) =>
      raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  static bool isValidNumber(String raw) =>
      RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(normalizeNumber(raw));

  /// Vehicles the signed-in user owns plus vehicles a transporter assigned
  /// to them, newest first.
  static Stream<List<Vehicle>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    late StreamController<List<Vehicle>> out;
    List<Vehicle>? owned;
    List<Vehicle>? assigned;
    final subs = <StreamSubscription<dynamic>>[];
    void emit() {
      // Wait until both queries have answered so the first event is complete.
      if (owned == null || assigned == null) return;
      final byId = {for (final v in [...owned!, ...assigned!]) v.id: v};
      final list = byId.values.toList()..sort((a, b) => newestFirst(a.createdAt, b.createdAt));
      out.add(list);
    }

    out = StreamController<List<Vehicle>>(
      onListen: () {
        subs.add(_col.where('ownerId', isEqualTo: uid).snapshots().listen((s) {
          owned = s.docs.map(Vehicle.fromDoc).toList();
          emit();
        }, onError: out.addError));
        subs.add(_col.where('assignedDriverId', isEqualTo: uid).snapshots().listen((s) {
          assigned = s.docs.map(Vehicle.fromDoc).toList();
          emit();
        }, onError: out.addError));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  static Future<List<Vehicle>> fetchMyActive() async {
    final uid = Backend.requireUid();
    final results = await Future.wait([
      _col.where('ownerId', isEqualTo: uid).get(),
      _col.where('assignedDriverId', isEqualTo: uid).get(),
    ]);
    final byId = {for (final s in results) for (final d in s.docs) d.id: Vehicle.fromDoc(d)};
    return byId.values.where((v) => v.isActive).toList();
  }

  /// Transporter: give [vehicleId] to one of the active drivers, or take it
  /// back with null. Rules check the driver is an active member.
  static Future<void> assignDriver(String vehicleId, String? driverId) => _col.doc(vehicleId).update({
        'assignedDriverId': driverId ?? FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Storage path for a vehicle's RC image; the owner uid in the path is what
  /// storage.rules checks.
  /// `vehicle_numbers/{number}` reserves a registration number for one
  /// vehicle; rules refuse a second create, which blocks duplicates across
  /// accounts.
  static DocumentReference<Map<String, dynamic>> _numberRef(String number) =>
      Backend.db.collection('vehicle_numbers').doc(number);

  /// Throws [DuplicateVehicleException] if [number] belongs to a vehicle other
  /// than [exceptVehicleId].
  static Future<void> _ensureNumberFree(String number, {String? exceptVehicleId}) async {
    try {
      final snap = await _numberRef(number).get();
      if (snap.exists && snap.data()?['vehicleId'] != exceptVehicleId) throw DuplicateVehicleException();
    } on FirebaseException catch (e) {
      // Rules deny reads of another owner's reservation only on malformed ids.
      if (e.code == 'permission-denied') throw DuplicateVehicleException();
      rethrow;
    }
  }

  // LATER(paid): RC photos need Firebase Storage (Blaze plan).
  static String rcImagePath(String ownerId, String vehicleId) => 'vehicles/$ownerId/$vehicleId/rc.jpg';

  static Future<String> _uploadRc(String uid, String vehicleId, Uint8List bytes) =>
      Backend.upload(rcImagePath(uid, vehicleId), bytes, 'image/jpeg');

  /// Creates a vehicle; uploads [rcImage] first (if given) so the document is
  /// written once with its `rcImageUrl`.
  static Future<String> add({
    required String number,
    required String type,
    required num capacity,
    required String rcNumber,
    Uint8List? rcImage,
    VehicleProfile profile = const VehicleProfile(),
  }) async {
    if (!profile.valid) throw ArgumentError('Invalid vehicle profile');
    final uid = Backend.requireUid();
    final ref = _col.doc();
    final normalized = normalizeNumber(number);
    await _ensureNumberFree(normalized);
    final rcImageUrl = rcImage == null ? null : await _uploadRc(uid, ref.id, rcImage);
    final batch = Backend.db.batch();
    batch.set(_numberRef(normalized), {'ownerId': uid, 'vehicleId': ref.id, 'createdAt': FieldValue.serverTimestamp()});
    batch.set(ref, {
      'ownerId': uid,
      'number': normalized,
      'type': type,
      'capacity': capacity,
      'rcNumber': rcNumber.trim().toUpperCase(),
      'status': VehicleStatus.active,
      'availability': VehicleAvailability.available,
      'rcImageUrl': ?rcImageUrl,
      ...profile.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      // Lost a race for the same number.
      if (e.code == 'permission-denied') throw DuplicateVehicleException();
      rethrow;
    }
    return ref.id;
  }

  /// Edits an existing vehicle. A new [rcImage] replaces the stored one.
  static Future<void> update({
    required String vehicleId,
    required String number,
    required String type,
    required num capacity,
    required String rcNumber,
    Uint8List? rcImage,
    VehicleProfile? profile,
  }) async {
    if (profile != null && !profile.valid) throw ArgumentError('Invalid vehicle profile');
    final uid = Backend.requireUid();
    final normalized = normalizeNumber(number);
    final old = await _col.doc(vehicleId).get();
    final oldNumber = old.data()?['number'] as String?;
    final numberChanged = oldNumber != normalized;
    if (numberChanged) await _ensureNumberFree(normalized, exceptVehicleId: vehicleId);
    final rcImageUrl = rcImage == null ? null : await _uploadRc(uid, vehicleId, rcImage);
    final batch = Backend.db.batch();
    if (numberChanged) {
      batch.set(_numberRef(normalized), {'ownerId': uid, 'vehicleId': vehicleId, 'createdAt': FieldValue.serverTimestamp()});
      if (oldNumber != null && oldNumber.isNotEmpty) {
        final oldRes = await _numberRef(oldNumber).get();
        if (oldRes.data()?['vehicleId'] == vehicleId) batch.delete(_numberRef(oldNumber));
      }
    }
    batch.update(_col.doc(vehicleId), {
      'number': normalized,
      'type': type,
      'capacity': capacity,
      'rcNumber': rcNumber.trim().toUpperCase(),
      'rcImageUrl': ?rcImageUrl,
      if (profile != null) ...profile.toUpdate(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (numberChanged && e.code == 'permission-denied') throw DuplicateVehicleException();
      rethrow;
    }
  }

  /// Saves insurance/PUC/fitness/permit details and the next service date.
  /// Empty entries are removed.
  static Future<void> saveDocuments(String vehicleId, Map<String, VehicleDocInfo> docs, {DateTime? nextServiceDate, DateTime? nextTyreCheckDate}) async {
    await _col.doc(vehicleId).update({
      'docs': {
        for (final e in docs.entries)
          if (VehicleDocKind.all.contains(e.key) && !e.value.isEmpty) e.key: e.value.toMap(),
      },
      'nextServiceDate': nextServiceDate == null ? FieldValue.delete() : Timestamp.fromDate(nextServiceDate),
      'nextTyreCheckDate': nextTyreCheckDate == null ? FieldValue.delete() : Timestamp.fromDate(nextTyreCheckDate),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await DocExpiryService.syncVehicle(vehicleId);
  }

  /// Owner switches between available and maintenance. on_trip is managed by
  /// bookings and suspended by admins.
  static Future<void> setAvailability(String vehicleId, String availability) {
    if (availability != VehicleAvailability.available && availability != VehicleAvailability.maintenance) {
      throw ArgumentError.value(availability, 'availability');
    }
    return _col.doc(vehicleId).update({'availability': availability, 'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> setActive(String vehicleId, bool active) {
    return _col.doc(vehicleId).update({
      'status': active ? VehicleStatus.active : VehicleStatus.inactive,
    });
  }
}
