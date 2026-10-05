import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/saved_search.dart';
import 'backend.dart';

class SearchLimitException implements Exception {
  @override
  String toString() => 'SearchLimitException';
}

/// Saved load / truck searches, private to the user.
class SavedSearchService {
  SavedSearchService._();

  static CollectionReference<Map<String, dynamic>> _col([String? uid]) =>
      Backend.db.collection('users').doc(uid ?? Backend.requireUid()).collection('saved_searches');

  static Stream<List<SavedSearch>> watch(String kind) {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col(uid).where('kind', isEqualTo: kind).snapshots().map((s) {
      final list = [for (final d in s.docs) SavedSearch.fromDoc(d.id, d.data())];
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  static Future<String> save({required String kind, required String name, required Map<String, Object?> filter}) async {
    final n = name.trim();
    if (!SearchKind.all.contains(kind)) throw ArgumentError.value(kind, 'kind');
    if (n.isEmpty || n.length > 40) throw ArgumentError.value(name, 'name');
    if (filter.isEmpty) throw ArgumentError.value(filter, 'filter', 'nothing to save');
    final col = _col();
    if ((await col.where('kind', isEqualTo: kind).get()).size >= SavedSearch.maxPerKind) throw SearchLimitException();
    final ref = col.doc();
    await ref.set({'kind': kind, 'name': n, 'filter': filter, 'createdAt': FieldValue.serverTimestamp()});
    return ref.id;
  }

  static Future<void> delete(String id) => _col().doc(id).delete();
}
