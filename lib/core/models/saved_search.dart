import 'package:cloud_firestore/cloud_firestore.dart';

class SearchKind {
  SearchKind._();
  static const loads = 'loads';
  static const trucks = 'trucks';
  static const all = [loads, trucks];
}

/// `users/{uid}/saved_searches/{id}`: a named filter the user reuses.
class SavedSearch {
  /// At most this many per kind (the app enforces it; rules cannot count).
  static const maxPerKind = 10;

  final String id;
  final String kind;
  final String name;
  final Map<String, dynamic> filter;
  final DateTime? createdAt;

  const SavedSearch({required this.id, required this.kind, required this.name, required this.filter, this.createdAt});

  factory SavedSearch.fromDoc(String id, Map<String, dynamic> d) => SavedSearch(
        id: id,
        kind: d['kind'] as String? ?? SearchKind.loads,
        name: d['name'] as String? ?? '',
        filter: Map<String, dynamic>.from((d['filter'] as Map?) ?? const {}),
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}
