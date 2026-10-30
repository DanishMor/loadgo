import 'dart:convert';

import 'package:flutter/services.dart';

import '../constants/logistics.dart';

/// E15: the vehicle catalog, shipped as an asset (assets/vehicles/catalog.json), not read from Firestore.
/// Every number is approximate and typical for India, not a legal limit; the owner corrects them in
/// docs/VEHICLE_REVIEW.csv. Names and "choose when" lines live in the string tables: `vc_<id>` and
/// `vcWhen_<id>`; typical goods are `vcGoods_<goods>`; body types reuse `body_<type>`.
class VehicleSpec {
  final String id;
  final String group;

  /// The id loads and vehicles already store (`vehicleType`), when this type has one (vehicle_type.dart).
  final String? legacyId;

  /// Tyres on each axle, front first: [2, 4] is a 6-wheeler with a dual rear axle.
  final List<int> axles;

  /// Load space in feet. Height 0 is open to the sky; all three are 0 for a crane (nothing is loaded).
  final double lengthFt, widthFt, heightFt;

  /// Typical payload in tonnes (lifting capacity for a crane).
  final double minTons, maxTons;
  final List<String> goods;
  final List<String> bodies;

  /// 1 (cheapest) to 5: a hint for the cards, never a fare.
  final int priceBand;

  /// A crane: [minTons]..[maxTons] is what it lifts, not what it carries.
  final bool lifts;

  const VehicleSpec({
    required this.id,
    required this.group,
    required this.axles,
    required this.lengthFt,
    required this.widthFt,
    required this.heightFt,
    required this.minTons,
    required this.maxTons,
    required this.goods,
    required this.bodies,
    required this.priceBand,
    this.legacyId,
    this.lifts = false,
  });

  int get wheels => axles.fold(0, (a, b) => a + b);
  bool get open => heightFt == 0 && lengthFt > 0;
  String get nameKey => 'vc_$id';
  String get whenKey => 'vcWhen_$id';

  /// Load space in cubic feet; 0 when it is open or a crane.
  double get volumeCft => open ? 0 : lengthFt * widthFt * heightFt;

  /// Can it carry [tons]? Never true for a crane.
  bool carries(double tons) => !lifts && tons > 0 && tons <= maxTons;

  /// Defensive: a bad row gives null, never a throw.
  static VehicleSpec? fromMap(Object? raw) {
    if (raw is! Map) return null;
    double? d(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    List<String> strings(Object? v) => v is List ? [for (final x in v) if (x is String && x.isNotEmpty) x] : const [];
    final id = raw['id'], group = raw['group'];
    final axles = raw['axles'];
    final l = d(raw['lengthFt']), w = d(raw['widthFt']), h = d(raw['heightFt']), lo = d(raw['minTons']), hi = d(raw['maxTons']);
    final band = raw['priceBand'];
    if (id is! String || id.isEmpty || group is! String || axles is! List || l == null || w == null || h == null || lo == null || hi == null || band is! int) {
      return null;
    }
    final tyres = [for (final a in axles) if (a is int) a];
    if (tyres.length != axles.length) return null;
    final legacy = raw['legacyId'];
    return VehicleSpec(
      id: id,
      group: group,
      legacyId: legacy is String && legacy.isNotEmpty ? legacy : null,
      axles: List.unmodifiable(tyres),
      lengthFt: l,
      widthFt: w,
      heightFt: h,
      minTons: lo,
      maxTons: hi,
      goods: List.unmodifiable(strings(raw['goods'])),
      bodies: List.unmodifiable(strings(raw['bodies'])),
      priceBand: band,
      lifts: raw['lifts'] == true,
    );
  }
}

class VehicleCatalog {
  VehicleCatalog._();

  static const asset = 'assets/vehicles/catalog.json';
  static const groups = ['two_wheeler', 'three_wheeler', 'lcv', 'icv', 'hcv', 'container', 'trailer', 'special'];
  static const goodsKinds = ['parcels', 'food', 'household', 'fmcg', 'building', 'produce', 'furniture', 'machinery', 'steel', 'liquids', 'coldchain', 'vehicles', 'sand', 'heavy', 'containers'];

  static List<VehicleSpec>? _cache;

  /// Parses the catalog JSON; rows that do not parse are dropped (the validator reports them).
  static List<VehicleSpec> parse(String json) {
    try {
      final root = jsonDecode(json);
      final rows = root is Map ? root['vehicles'] : null;
      if (rows is! List) return const [];
      return List.unmodifiable([for (final r in rows) ?VehicleSpec.fromMap(r)]);
    } catch (_) {
      return const [];
    }
  }

  /// The catalog from the app bundle, kept once it has read well. Empty (never a throw) if the asset cannot be
  /// read; an empty result is not kept, so a retry reads again.
  static Future<List<VehicleSpec>> load({AssetBundle? bundle}) async {
    if (_cache != null) return _cache!;
    try {
      final list = parse(await (bundle ?? rootBundle).loadString(asset));
      if (list.isNotEmpty) _cache = list;
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// The catalog entry for a `vehicleType` stored on a load, offer or truck post: its own id, or the first
  /// type that maps to that legacy id ('14ft' -> lcv_14ft).
  static VehicleSpec? forType(List<VehicleSpec> all, String type) {
    for (final v in all) {
      if (v.id == type) return v;
    }
    for (final v in all) {
      if (v.legacyId == type) return v;
    }
    return null;
  }

  static VehicleSpec? byId(List<VehicleSpec> all, String id) {
    for (final v in all) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// Everything wrong with [json], one line each; empty when it is good. Used by the test and by whoever edits
  /// the file after the owner's review.
  static List<String> validate(String json) {
    final out = <String>[];
    Object? root;
    try {
      root = jsonDecode(json);
    } catch (e) {
      return ['not JSON: $e'];
    }
    final rows = root is Map ? root['vehicles'] : null;
    if (rows is! List || rows.isEmpty) return ['no "vehicles" list'];
    final seen = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final v = VehicleSpec.fromMap(rows[i]);
      if (v == null) {
        out.add('row $i: missing or wrong field');
        continue;
      }
      final at = v.id;
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v.id)) out.add('$at: id must be lower_snake_case');
      if (!seen.add(v.id)) out.add('$at: duplicate id');
      if (!groups.contains(v.group)) out.add('$at: unknown group ${v.group}');
      if (v.axles.length < 2 || v.axles.any((t) => t < 1 || t > 4)) out.add('$at: axles must be 2 or more, 1 to 4 tyres each');
      if (v.wheels < 2 || v.wheels > 30) out.add('$at: ${v.wheels} wheels');
      if (v.minTons < 0 || v.maxTons <= 0 || v.minTons > v.maxTons) out.add('$at: payload ${v.minTons}..${v.maxTons}');
      if (v.priceBand < 1 || v.priceBand > 5) out.add('$at: priceBand ${v.priceBand}');
      if (v.goods.isEmpty || v.goods.any((g) => !goodsKinds.contains(g))) out.add('$at: goods ${v.goods}');
      if (v.bodies.isEmpty || v.bodies.any((b) => !BodyType.all.contains(b))) out.add('$at: bodies ${v.bodies}');
      if (v.lifts) {
        if (v.lengthFt != 0 || v.widthFt != 0 || v.heightFt != 0) out.add('$at: a crane carries nothing, sizes must be 0');
      } else {
        if (v.lengthFt <= 0 || v.lengthFt > 80 || v.widthFt <= 0 || v.widthFt > 10) out.add('$at: size ${v.lengthFt} x ${v.widthFt}');
        if (v.heightFt < 0 || v.heightFt > 14) out.add('$at: height ${v.heightFt}');
        if (v.widthFt > v.lengthFt) out.add('$at: wider than long');
      }
    }
    return out;
  }
}
