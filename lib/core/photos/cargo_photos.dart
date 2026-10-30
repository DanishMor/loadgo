import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/backend.dart';
import 'photo_quality.dart';
import 'photo_service.dart';
import 'vehicle_photos.dart' show PhotoNotClear;

/// E19: photos of the goods a customer adds to a load. Three fixed slots, so a load never holds more than three
/// files: Storage loads/{loadId}/cargo/{slot} and a record at loads/{loadId}/cargo/{slot} (firestore.rules and
/// storage.rules: the shipper writes while the load is open; readable wherever the load is).
enum CargoSlot {
  goods1,
  goods2,
  goods3;

  static CargoSlot? parse(Object? s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

class CargoPhotoRecord {
  final CargoSlot slot;
  final String path;
  final DateTime? at;
  const CargoPhotoRecord({required this.slot, required this.path, this.at});

  /// Defensive: a record that does not parse, or points outside its own load, gives null.
  static CargoPhotoRecord? fromMap(String loadId, Map<String, dynamic>? m) {
    if (m == null) return null;
    final slot = CargoSlot.parse(m['slot']);
    final path = m['path'];
    if (slot == null || path != CargoPhotoService.path(loadId, slot)) return null;
    final at = m['at'];
    return CargoPhotoRecord(slot: slot, path: path as String, at: at is Timestamp ? at.toDate() : null);
  }
}

class CargoPhotoService {
  CargoPhotoService._();

  static const maxBytes = 3 * 1024 * 1024 - 1;

  static String path(String loadId, CargoSlot slot) => 'loads/$loadId/cargo/${slot.name}';

  static CollectionReference<Map<String, dynamic>> _cargo(String loadId) => Backend.db.collection('loads').doc(loadId).collection('cargo');

  static bool _safe(String id) => RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id);

  /// The first empty slot, or null when all three are used.
  static CargoSlot? freeSlot(Iterable<CargoPhotoRecord> records) {
    final used = {for (final r in records) r.slot};
    return CargoSlot.values.where((s) => !used.contains(s)).firstOrNull;
  }

  /// Same checks as vehicle photos: on-device quality (unless [anyway]), metadata removed (GPS place, phone model),
  /// under 3 MB, then the file and its record. Throws [PhotoNotClear] or [PhotoRejected].
  static Future<CargoPhotoRecord> upload(String loadId, CargoSlot slot, PickedPhoto photo, {bool anyway = false, Future<PhotoQuality> Function(Uint8List)? measure}) async {
    if (Backend.uid == null || !_safe(loadId)) throw const PhotoRejected('target');
    if (photo.bytes.isEmpty) throw const PhotoRejected('empty');
    if (!PhotoService.mimes.containsKey(photo.mime)) throw const PhotoRejected('type');
    final clean = photo.mime == 'image/jpeg' ? stripJpegMetadata(photo.bytes) : photo.bytes;
    if (clean.length > maxBytes) throw const PhotoRejected('too_big');
    if (!anyway) {
      final q = await (measure ?? PhotoQuality.measure)(clean);
      if (!q.ok) throw PhotoNotClear(q.issues);
    }
    final p = path(loadId, slot);
    await PhotoService.gateway.put(p, clean, photo.mime);
    await _cargo(loadId).doc(slot.name).set({'slot': slot.name, 'path': p, 'at': FieldValue.serverTimestamp()});
    return CargoPhotoRecord(slot: slot, path: p);
  }

  /// The goods photos of a load (at most three records), live for the shipper's screen.
  static Stream<List<CargoPhotoRecord>> watch(String loadId) => _cargo(loadId)
      .limit(CargoSlot.values.length)
      .snapshots()
      .map((s) => [for (final d in s.docs) ?CargoPhotoRecord.fromMap(loadId, d.data())]..sort((a, b) => a.slot.index.compareTo(b.slot.index)));

  /// One read for a driver looking at the load; empty on any error (the load must show without them).
  static Future<List<CargoPhotoRecord>> list(String loadId) async {
    try {
      final s = await _cargo(loadId).limit(CargoSlot.values.length).get();
      return [for (final d in s.docs) ?CargoPhotoRecord.fromMap(loadId, d.data())]..sort((a, b) => a.slot.index.compareTo(b.slot.index));
    } catch (_) {
      return const [];
    }
  }

  /// The shipper takes a photo off: the record first (so nobody is pointed at a missing file), then the file.
  static Future<void> remove(String loadId, CargoSlot slot) async {
    await _cargo(loadId).doc(slot.name).delete();
    try {
      await PhotoService.gateway.delete(path(loadId, slot));
    } catch (_) {
      // A file left behind is only storage; the record is gone, so nobody sees it.
    }
  }
}
