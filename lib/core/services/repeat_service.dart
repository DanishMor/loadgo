import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/repeat.dart';
import 'backend.dart';

class TemplateLimitException implements Exception {
  @override
  String toString() => 'TemplateLimitException';
}

class BlockLimitException implements Exception {
  @override
  String toString() => 'BlockLimitException';
}

/// Customer shortcuts: load templates, favourite drivers and the block list.
/// All private to the customer (`users/{uid}/...`).
class RepeatService {
  RepeatService._();

  static DocumentReference<Map<String, dynamic>> _me([String? uid]) => Backend.db.collection('users').doc(uid ?? Backend.requireUid());

  // ---- templates ----

  static Stream<List<LoadTemplate>> watchTemplates() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _me(uid).collection('load_templates').snapshots().map((s) => [
          for (final d in s.docs) LoadTemplate.fromDoc(d.id, d.data()),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
  }

  static Future<String> saveTemplate(LoadTemplate t) async {
    final col = _me().collection('load_templates');
    if (t.name.trim().isEmpty || t.name.trim().length > 40) throw ArgumentError.value(t.name, 'name');
    if ((await col.get()).size >= LoadTemplate.maxTemplates) throw TemplateLimitException();
    final ref = col.doc();
    await ref.set({...t.toMap(), 'name': t.name.trim(), 'createdAt': FieldValue.serverTimestamp()});
    return ref.id;
  }

  static Future<void> deleteTemplate(String id) => _me().collection('load_templates').doc(id).delete();

  // ---- favourite drivers ----

  static Stream<List<FavouriteDriver>> watchFavourites() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _me(uid).collection('favourite_drivers').snapshots().map((s) => [
          for (final d in s.docs) FavouriteDriver.fromDoc(d.id, d.data()),
        ]..sort((a, b) => a.name.compareTo(b.name)));
  }

  static Future<void> addFavourite({required String driverId, String name = '', String vehicleNumber = ''}) async {
    final batch = Backend.db.batch();
    batch.set(_me().collection('favourite_drivers').doc(driverId), {
      'name': name,
      'vehicleNumber': vehicleNumber,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // A driver cannot be both a favourite and blocked.
    batch.delete(_me().collection('blocked_drivers').doc(driverId));
    await batch.commit();
  }

  /// Ids of the favourite drivers (for a load limited to them).
  static Future<List<String>> favouriteIds([String? uid]) async =>
      [for (final d in (await _me(uid).collection('favourite_drivers').get()).docs) d.id];

  static Future<void> removeFavourite(String driverId) => _me().collection('favourite_drivers').doc(driverId).delete();

  // ---- block list ----

  static Stream<List<BlockedDriver>> watchBlocked() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _me(uid).collection('blocked_drivers').snapshots().map((s) => [
          for (final d in s.docs) BlockedDriver.fromDoc(d.id, d.data()),
        ]..sort((a, b) => a.name.compareTo(b.name)));
  }

  /// Ids the signed-in customer has blocked (at most [BlockedDriver.maxBlocked]).
  static Future<List<String>> blockedIds([String? uid]) async {
    final snap = await _me(uid).collection('blocked_drivers').get();
    return [for (final d in snap.docs) d.id].take(BlockedDriver.maxBlocked).toList();
  }

  static Future<void> blockDriver({required String driverId, String name = ''}) async {
    final col = _me().collection('blocked_drivers');
    final existing = await col.get();
    if (existing.size >= BlockedDriver.maxBlocked && !existing.docs.any((d) => d.id == driverId)) throw BlockLimitException();
    final batch = Backend.db.batch();
    batch.set(col.doc(driverId), {'name': name, 'createdAt': FieldValue.serverTimestamp()});
    batch.delete(_me().collection('favourite_drivers').doc(driverId));
    await batch.commit();
  }

  static Future<void> unblockDriver(String driverId) => _me().collection('blocked_drivers').doc(driverId).delete();
}
