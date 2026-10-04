import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../constants/logistics.dart';
import '../models/vehicle.dart';
import 'backend.dart';

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
  }) async {
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
  }) async {
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
  static Future<void> saveDocuments(String vehicleId, Map<String, VehicleDocInfo> docs, {DateTime? nextServiceDate}) {
    return _col.doc(vehicleId).update({
      'docs': {
        for (final e in docs.entries)
          if (VehicleDocKind.all.contains(e.key) && !e.value.isEmpty) e.key: e.value.toMap(),
      },
      'nextServiceDate': nextServiceDate == null ? FieldValue.delete() : Timestamp.fromDate(nextServiceDate),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
