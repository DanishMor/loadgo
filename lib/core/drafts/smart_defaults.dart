import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/vehicle_type.dart';
import '../services/backend.dart';

/// A goods preset: what a customer sent before.
class GoodsPreset {
  final String cargo;
  final num weight;
  final String vehicleType;
  const GoodsPreset(this.cargo, this.weight, this.vehicleType);

  Map<String, Object?> toJson() => {'cargo': cargo, 'weight': weight, 'vehicleType': vehicleType};

  static GoodsPreset? fromJson(Object? m) {
    if (m is! Map || m['cargo'] is! String || m['weight'] is! num || m['vehicleType'] is! String) return null;
    final w = m['weight'] as num;
    if (w <= 0 || w > 100) return null;
    return GoodsPreset(m['cargo'] as String, w, m['vehicleType'] as String);
  }
}

class LastRoute {
  final String pickup;
  final String drop;
  const LastRoute(this.pickup, this.drop);
}

/// Smart defaults for the Post Load form (MASTER-6 Task 16): the last route,
/// the usual goods and a vehicle that fits the weight. Kept on this phone.
class SmartDefaults {
  SmartDefaults._();

  static const maxPresets = 5;

  /// The smallest active type that can carry [weight] tonnes; among equals the
  /// one whose range starts closest below the weight. Null when nothing fits
  /// or the weight is not a usable number.
  static VehicleTypeInfo? suggestVehicle(num? weight, Iterable<VehicleTypeInfo> types) {
    if (weight == null || weight <= 0 || weight > 100) return null;
    VehicleTypeInfo? best;
    for (final t in types) {
      if (!t.active || !t.fits(weight)) continue;
      if (best == null || t.maxTons < best.maxTons || (t.maxTons == best.maxTons && t.minTons > best.minTons)) best = t;
    }
    return best;
  }

  /// Most recent first, one per cargo + vehicle, at most [maxPresets].
  static List<GoodsPreset> pushPreset(List<GoodsPreset> old, GoodsPreset p) {
    final out = [p, for (final o in old) if (!(o.cargo == p.cargo && o.vehicleType == p.vehicleType)) o];
    return out.take(maxPresets).toList();
  }

  static String get _routeKey => 'last_route_${Backend.uid ?? 'anon'}';
  static String get _goodsKey => 'goods_presets_${Backend.uid ?? 'anon'}';

  static Future<LastRoute?> lastRoute() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_routeKey);
      if (raw == null) return null;
      final m = jsonDecode(raw);
      if (m is Map && m['pickup'] is String && m['drop'] is String && (m['pickup'] as String).trim().length >= 2) return LastRoute(m['pickup'] as String, m['drop'] as String);
    } catch (_) {}
    return null;
  }

  static Future<List<GoodsPreset>> presets() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_goodsKey);
      if (raw == null) return const [];
      final list = jsonDecode(raw);
      if (list is List) return [for (final x in list) ?GoodsPreset.fromJson(x)].take(maxPresets).toList();
    } catch (_) {}
    return const [];
  }

  /// Remembers a posted load: its route and its goods.
  static Future<void> record({required String pickup, required String drop, required String cargo, required num weight, required String vehicleType}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pickup.trim().length >= 2) {
        await prefs.setString(_routeKey, jsonEncode({'pickup': pickup.trim(), 'drop': drop.trim()}));
      }
      final p = GoodsPreset(cargo, weight, vehicleType);
      if (cargo.isNotEmpty && weight > 0 && weight <= 100) {
        final next = pushPreset(await presets(), p);
        await prefs.setString(_goodsKey, jsonEncode([for (final x in next) x.toJson()]));
      }
    } catch (_) {}
  }
}
