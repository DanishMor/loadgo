import 'package:cloud_firestore/cloud_firestore.dart';

/// Kind of a customer's saved place. Must stay in sync with firestore.rules.
class PlaceLabel {
  PlaceLabel._();
  static const home = 'home';
  static const office = 'office';
  static const warehouse = 'warehouse';
  static const factory = 'factory';
  static const port = 'port';
  static const cfs = 'cfs';

  static const all = [home, office, warehouse, factory, port, cfs];
}

/// `users/{uid}/saved_places/{id}`.
class SavedPlace {
  final String id;
  final String label;
  final String name;
  final String address;

  const SavedPlace({required this.id, required this.label, required this.name, required this.address});

  factory SavedPlace.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SavedPlace(
      id: doc.id,
      label: d['label'] as String? ?? PlaceLabel.home,
      name: d['name'] as String? ?? '',
      address: d['address'] as String? ?? '',
    );
  }
}
