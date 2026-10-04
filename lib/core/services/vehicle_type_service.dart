import 'package:flutter/foundation.dart';

import '../models/vehicle_type.dart';
import 'backend.dart';

/// Vehicle types from `config/vehicle_types` (`{types: [...]}`), falling
/// back to [defaultVehicleTypes]. Only admins can write the config (rules).
class VehicleTypeService {
  VehicleTypeService._();

  static final ValueNotifier<List<VehicleTypeInfo>> notifier =
      ValueNotifier<List<VehicleTypeInfo>>(defaultVehicleTypes);

  /// Active types, in config order.
  static List<VehicleTypeInfo> get types => notifier.value.where((t) => t.active).toList();

  static List<String> get ids => [for (final t in types) t.id];

  /// Type with [id] (including inactive or legacy ones), or null.
  static VehicleTypeInfo? byId(String? id) {
    for (final t in [...notifier.value, ...defaultVehicleTypes]) {
      if (t.id == id) return t;
    }
    return null;
  }

  static Future<void> refresh() async {
    try {
      final snap = await Backend.db.collection('config').doc('vehicle_types').get();
      notifier.value = parse(snap.data());
    } catch (_) {
      // Offline or not signed in: keep what we have.
    }
  }

  /// Config document -> types; empty or malformed configs fall back.
  static List<VehicleTypeInfo> parse(Map<String, dynamic>? data) {
    final raw = data?['types'];
    if (raw is! List) return defaultVehicleTypes;
    final list = [
      for (final m in raw)
        if (m is Map<String, dynamic>) VehicleTypeInfo.fromMap(m),
    ].where((t) => t.id.isNotEmpty).toList();
    return list.isEmpty ? defaultVehicleTypes : list;
  }

  /// Admin only (enforced by rules).
  static Future<void> save(List<VehicleTypeInfo> types) => Backend.db
      .collection('config')
      .doc('vehicle_types')
      .set({'types': [for (final t in types) t.toMap()]});

  @visibleForTesting
  static void reset() => notifier.value = defaultVehicleTypes;
}
