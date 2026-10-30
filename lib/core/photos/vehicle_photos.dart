import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/backend.dart';
import 'photo_quality.dart';
import 'photo_service.dart';

/// E18: the photos a driver takes of a vehicle. Files live in Storage at users/{uid}/vphotos/{vehicleId}/{slot}; a
/// small record per slot sits at vehicles/{vehicleId}/photos/{slot} (firestore.rules). The badge record
/// (vehicles/{vehicleId}/photos/badge) is written only by a verifier.
enum VehiclePhotoSlot {
  front,
  rear,
  left,
  right,
  load,
  plate,
  rc,
  cab;

  /// Seen from the road; customers may see these. Plate and RC stay with the owner and admins.
  bool get exterior => this != plate && this != rc;

  /// All but the cab are needed for the Photo-verified badge.
  static const required = [front, rear, left, right, load, plate, rc];

  static VehiclePhotoSlot? parse(Object? s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

enum VehiclePhotoStatus { pending, approved, rejected }

/// Why a verifier turned a photo down (the same list as firestore.rules).
const vehiclePhotoReasons = ['blurry', 'dark', 'wrong_view', 'plate_mismatch', 'other'];

class VehiclePhotoRecord {
  final VehiclePhotoSlot slot;
  final String path;
  final VehiclePhotoStatus status;
  final DateTime? at;
  final String? reason;
  const VehiclePhotoRecord({required this.slot, required this.path, required this.status, this.at, this.reason});

  /// Defensive: a record that does not parse gives null.
  static VehiclePhotoRecord? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final slot = VehiclePhotoSlot.parse(m['slot']);
    final path = m['path'];
    if (slot == null || path is! String || path.isEmpty) return null;
    final status = VehiclePhotoStatus.values.where((s) => s.name == m['status']).firstOrNull ?? VehiclePhotoStatus.pending;
    final at = m['at'];
    final reason = m['reason'];
    return VehiclePhotoRecord(
      slot: slot,
      path: path,
      status: status,
      at: at is Timestamp ? at.toDate() : null,
      reason: reason is String && vehiclePhotoReasons.contains(reason) ? reason : null,
    );
  }
}

/// The Photo-verified badge: valid until a date at most about six months after a verifier approved the set.
class PhotoBadge {
  final DateTime until;
  const PhotoBadge(this.until);

  static const validFor = Duration(days: 182);
  static const remindBefore = Duration(days: 14);

  static PhotoBadge? fromMap(Map<String, dynamic>? m) {
    final u = m?['until'];
    return u is Timestamp ? PhotoBadge(u.toDate()) : null;
  }

  bool activeAt(DateTime now) => now.isBefore(until);

  /// Time to take fresh photos: in the last two weeks, or already expired.
  bool remindAt(DateTime now) => !now.isBefore(until.subtract(remindBefore));
}

/// The set is ready for the badge when every required slot is approved.
bool readyForBadge(Iterable<VehiclePhotoRecord> records) {
  final approved = {for (final r in records) if (r.status == VehiclePhotoStatus.approved) r.slot};
  return VehiclePhotoSlot.required.every(approved.contains);
}

enum PlateCheck { match, mismatch, unread }

/// Compares the plate text read from the photo (OcrAdapter) with the vehicle number the driver typed, ignoring
/// spaces, dashes and case. Unread when the reader gave too little to judge. Advice only: a verifier decides.
PlateCheck checkPlate(String? read, String vehicleNumber) {
  String norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final r = norm(read ?? ''), n = norm(vehicleNumber);
  if (r.length < 6 || n.isEmpty) return PlateCheck.unread;
  return r == n ? PlateCheck.match : PlateCheck.mismatch;
}

/// The photo was not good enough; [issues] says why (the screen offers to retake or send anyway).
class PhotoNotClear implements Exception {
  final List<PhotoIssue> issues;
  const PhotoNotClear(this.issues);
}

class VehiclePhotoService {
  VehiclePhotoService._();

  static const maxBytes = 3 * 1024 * 1024 - 1;

  static String path(String uid, String vehicleId, VehiclePhotoSlot slot) => 'users/$uid/vphotos/$vehicleId/${slot.name}';

  static CollectionReference<Map<String, dynamic>> _photos(String vehicleId) => Backend.db.collection('vehicles').doc(vehicleId).collection('photos');

  /// Checks the photo on the phone, removes its metadata (GPS place, phone model), stores the file and writes a
  /// pending record. Throws [PhotoNotClear] unless [anyway], and [PhotoRejected] for a file that cannot be sent.
  static Future<VehiclePhotoRecord> upload(String vehicleId, VehiclePhotoSlot slot, PickedPhoto photo, {bool anyway = false, Future<PhotoQuality> Function(Uint8List)? measure}) async {
    final uid = Backend.uid;
    if (uid == null) throw const PhotoRejected('target');
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(vehicleId)) throw const PhotoRejected('target');
    if (photo.bytes.isEmpty) throw const PhotoRejected('empty');
    if (!PhotoService.mimes.containsKey(photo.mime)) throw const PhotoRejected('type');
    final clean = photo.mime == 'image/jpeg' ? stripJpegMetadata(photo.bytes) : photo.bytes;
    if (clean.length > maxBytes) throw const PhotoRejected('too_big');
    if (!anyway) {
      final q = await (measure ?? PhotoQuality.measure)(clean);
      if (!q.ok) throw PhotoNotClear(q.issues);
    }
    final p = path(uid, vehicleId, slot);
    await PhotoService.gateway.put(p, clean, photo.mime);
    await _photos(vehicleId).doc(slot.name).set({'slot': slot.name, 'path': p, 'status': 'pending', 'at': FieldValue.serverTimestamp()});
    return VehiclePhotoRecord(slot: slot, path: p, status: VehiclePhotoStatus.pending);
  }

  /// The owner's records of one vehicle (at most 8 documents).
  static Stream<List<VehiclePhotoRecord>> watch(String vehicleId) =>
      _photos(vehicleId).limit(9).snapshots().map((s) => [for (final d in s.docs) if (d.id != 'badge') ?VehiclePhotoRecord.fromMap(d.data())]);

  /// One read: the badge of a vehicle, or null.
  static Future<PhotoBadge?> badge(String vehicleId) async {
    try {
      return PhotoBadge.fromMap((await _photos(vehicleId).doc('badge').get()).data());
    } catch (_) {
      return null;
    }
  }
}
