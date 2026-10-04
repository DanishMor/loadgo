import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/saved_place.dart';
import 'backend.dart';

/// Thrown when the user already has [SavedPlaceService.maxPlaces] places.
class TooManyPlacesException implements Exception {}

class SavedPlaceService {
  SavedPlaceService._();

  static const maxPlaces = 20;

  static CollectionReference<Map<String, dynamic>> _col(String uid) =>
      Backend.db.collection('users').doc(uid).collection('saved_places');

  static Stream<List<SavedPlace>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col(uid).snapshots().map((s) {
      final list = s.docs.map(SavedPlace.fromDoc).toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  static Future<String> add({required String label, required String name, required String address}) async {
    final uid = Backend.requireUid();
    final existing = await _col(uid).count().get();
    if ((existing.count ?? 0) >= maxPlaces) throw TooManyPlacesException();
    final ref = await _col(uid).add({
      'label': label,
      'name': name.trim(),
      'address': address.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> delete(String id) => _col(Backend.requireUid()).doc(id).delete();
}
