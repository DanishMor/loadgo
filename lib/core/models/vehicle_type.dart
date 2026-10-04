/// One entry of `config/vehicle_types` (or the built-in fallback list).
///
/// [id] is what loads and vehicles store in their `vehicleType`/`type` field;
/// the legacy ids ('Bike', '3-Wheeler', 'Mini', '14ft', ...) are kept so
/// existing documents still match.
class VehicleTypeInfo {
  final String id;

  /// English fallback name for types added in Firestore without a
  /// translation key.
  final String name;

  /// Translation key for the display name, or null to use [name].
  final String? labelKey;

  /// Typical payload range in tonnes.
  final num minTons;
  final num maxTons;

  /// two_wheeler, three_wheeler, lcv, hcv, container, trailer.
  final String category;

  final bool active;

  const VehicleTypeInfo({
    required this.id,
    required this.name,
    required this.minTons,
    required this.maxTons,
    required this.category,
    this.labelKey,
    this.active = true,
  });

  /// Can this type carry [weightTons]?
  bool fits(num weightTons) => weightTons <= maxTons;

  factory VehicleTypeInfo.fromMap(Map<String, dynamic> m) => VehicleTypeInfo(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? m['id'] as String? ?? '',
        labelKey: m['labelKey'] as String?,
        minTons: m['minTons'] as num? ?? 0,
        maxTons: m['maxTons'] as num? ?? 0,
        category: m['category'] as String? ?? 'lcv',
        active: m['active'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (labelKey != null) 'labelKey': labelKey,
        'minTons': minTons,
        'maxTons': maxTons,
        'category': category,
        'active': active,
      };
}

/// Used until (or when) `config/vehicle_types` cannot be read.
const List<VehicleTypeInfo> defaultVehicleTypes = [
  VehicleTypeInfo(id: 'Bike', name: 'Bike', labelKey: 'vtBike', minTons: 0, maxTons: 0.02, category: 'two_wheeler'),
  VehicleTypeInfo(id: 'Scooter', name: 'Scooter', labelKey: 'vtScooter', minTons: 0, maxTons: 0.03, category: 'two_wheeler'),
  VehicleTypeInfo(id: 'EV 2W', name: 'EV 2W', labelKey: 'vtEv2w', minTons: 0, maxTons: 0.03, category: 'two_wheeler'),
  VehicleTypeInfo(id: 'Cycle', name: 'Cycle', labelKey: 'vtCycle', minTons: 0, maxTons: 0.015, category: 'two_wheeler'),
  VehicleTypeInfo(id: '3-Wheeler', name: '3W goods auto', labelKey: 'vt3w', minTons: 0.3, maxTons: 1, category: 'three_wheeler'),
  VehicleTypeInfo(id: 'Mini', name: 'Mini truck', labelKey: 'vtMini', minTons: 0.75, maxTons: 2, category: 'lcv'),
  VehicleTypeInfo(id: '14ft', name: '14 ft', minTons: 2.5, maxTons: 4, category: 'lcv'),
  VehicleTypeInfo(id: '17ft', name: '17 ft', minTons: 4, maxTons: 5, category: 'lcv'),
  VehicleTypeInfo(id: '19ft', name: '19 ft', minTons: 5, maxTons: 7, category: 'hcv'),
  VehicleTypeInfo(id: '20ft', name: '20 ft', minTons: 6, maxTons: 8, category: 'hcv'),
  VehicleTypeInfo(id: '22ft', name: '22 ft', minTons: 8, maxTons: 10, category: 'hcv'),
  VehicleTypeInfo(id: '24ft', name: '24 ft', minTons: 9, maxTons: 12, category: 'hcv'),
  VehicleTypeInfo(id: '32ft', name: '32 ft', minTons: 7, maxTons: 18, category: 'hcv'),
  VehicleTypeInfo(id: 'Container', name: 'Container', labelKey: 'vtContainer', minTons: 7, maxTons: 26, category: 'container'),
  VehicleTypeInfo(id: 'Trailer', name: 'Trailer', labelKey: 'vtTrailer', minTons: 20, maxTons: 40, category: 'trailer'),
  VehicleTypeInfo(id: 'Open body', name: 'Open body', labelKey: 'vtOpenBody', minTons: 5, maxTons: 25, category: 'hcv'),
];
