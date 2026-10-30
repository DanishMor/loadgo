import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/vehicle_type.dart';
import 'package:transport_app/core/vehicles/vehicle_catalog.dart';

/// E15: the vehicle catalog asset, its validator, its names in 12 languages and the owner review sheet.
void main() {
  final json = File(VehicleCatalog.asset).readAsStringSync();
  final all = VehicleCatalog.parse(json);

  test('the shipped catalog is valid and has every type the plan asks for', () {
    expect(VehicleCatalog.validate(json), isEmpty);
    expect(all.map((v) => v.id), containsAll([
      'bike', 'auto_3w', 'e_loader', 'e_rickshaw_loader', 'mini_truck', 'pickup_8ft', 'lcv_14ft', 'lcv_17ft', 'icv_19ft', 'icv_20ft',
      'icv_22ft', 'icv_24ft', 'box_32ft_sxl', 'box_32ft_mxl', 'truck_6w', 'truck_10w', 'truck_12w', 'truck_14w', 'container_20ft',
      'container_40ft', 'trailer_flatbed', 'low_bed', 'tipper', 'tanker', 'reefer', 'car_carrier', 'hydra_crane',
    ]));
    expect(all.length, 27);
  });

  test('wheels add up from the axles; the N-wheelers really have N wheels', () {
    final w = {for (final v in all) v.id: v.wheels};
    expect(w['bike'], 2);
    expect(w['auto_3w'], 3);
    expect(w['mini_truck'], 4);
    expect(w['truck_6w'], 6);
    expect(w['truck_10w'], 10);
    expect(w['truck_12w'], 12);
    expect(w['truck_14w'], 14);
    expect(VehicleCatalog.byId(all, 'box_32ft_mxl')!.axles.length, greaterThan(VehicleCatalog.byId(all, 'box_32ft_sxl')!.axles.length));
  });

  test('legacy ids point at types loads already store, so old loads keep matching', () {
    final known = defaultVehicleTypes.map((t) => t.id).toSet();
    for (final v in all.where((v) => v.legacyId != null)) {
      expect(known, contains(v.legacyId), reason: v.id);
    }
    expect(VehicleCatalog.byId(all, 'lcv_14ft')!.legacyId, '14ft');
  });

  test('payload grows with the truck size along the ft series', () {
    final series = ['mini_truck', 'lcv_14ft', 'lcv_17ft', 'icv_19ft', 'icv_20ft', 'icv_22ft', 'icv_24ft'];
    for (var i = 1; i < series.length; i++) {
      final a = VehicleCatalog.byId(all, series[i - 1])!, b = VehicleCatalog.byId(all, series[i])!;
      expect(b.maxTons, greaterThanOrEqualTo(a.maxTons), reason: '${a.id} -> ${b.id}');
      expect(b.lengthFt, greaterThan(a.lengthFt));
    }
  });

  test('a crane lifts, it does not carry; open bodies have no volume', () {
    final crane = VehicleCatalog.byId(all, 'hydra_crane')!;
    expect(crane.lifts, isTrue);
    expect(crane.carries(1), isFalse);
    expect(VehicleCatalog.byId(all, 'truck_6w')!.open, isTrue);
    expect(VehicleCatalog.byId(all, 'truck_6w')!.volumeCft, 0);
    expect(VehicleCatalog.byId(all, 'lcv_14ft')!.volumeCft, 14 * 6 * 6);
    expect(VehicleCatalog.byId(all, 'lcv_14ft')!.carries(3), isTrue);
    expect(VehicleCatalog.byId(all, 'lcv_14ft')!.carries(5), isFalse);
  });

  test('every name, "choose when" line and goods word exists in all 12 languages', () {
    final keys = <String>{
      for (final v in all) ...[v.nameKey, v.whenKey],
      for (final g in VehicleCatalog.goodsKinds) 'vcGoods_$g',
    };
    for (final k in keys) {
      for (final l in AppLanguage.values) {
        final s = T.data[k]?[l];
        expect(s, isNotNull, reason: '$k ${l.name}');
        expect(s!.trim(), isNotEmpty, reason: '$k ${l.name}');
      }
    }
    for (final v in all) {
      for (final b in v.bodies) {
        expect(T.data['body_$b'], isNotNull, reason: b);
      }
    }
    // Hindi first: Hindi is not just the English copied.
    for (final v in all) {
      expect(T.data[v.whenKey]![AppLanguage.hindi], isNot(T.data[v.whenKey]![AppLanguage.english]));
    }
  });

  test('no maker or brand name anywhere in the catalog or its words', () {
    final words = [json, for (final v in all) ...[for (final l in AppLanguage.values) T.data[v.nameKey]![l]!, T.data[v.whenKey]![AppLanguage.english]!]].join(' ').toLowerCase();
    for (final brand in ['tata', 'ashok', 'leyland', 'mahindra', 'eicher', 'bharatbenz', 'piaggio', 'maruti', 'jcb', 'volvo', 'scania', 'bajaj', 'force motors']) {
      expect(words.contains(brand), isFalse, reason: brand);
    }
  });

  test('the validator catches bad rows and the parser never throws', () {
    expect(VehicleCatalog.parse('not json'), isEmpty);
    expect(VehicleCatalog.parse('{"vehicles": 5}'), isEmpty);
    expect(VehicleCatalog.validate('{}'), isNotEmpty);
    expect(VehicleSpec.fromMap({'id': 'x'}), isNull);
    expect(VehicleSpec.fromMap({'id': 'x', 'group': 'lcv', 'axles': [2, 'four'], 'lengthFt': 1, 'widthFt': 1, 'heightFt': 1, 'minTons': 0, 'maxTons': 1, 'priceBand': 1}), isNull);
    const bad = '{"vehicles": ['
        '{"id": "Bad Id", "group": "spaceship", "axles": [9], "lengthFt": 3, "widthFt": 9, "heightFt": 20, "minTons": 5, "maxTons": 1, "goods": ["gold"], "bodies": ["glass"], "priceBand": 7},'
        '{"id": "ok", "group": "lcv", "axles": [2, 2], "lengthFt": 7, "widthFt": 4, "heightFt": 5, "minTons": 1, "maxTons": 2, "goods": ["fmcg"], "bodies": ["open"], "priceBand": 2},'
        '{"id": "ok", "group": "lcv", "axles": [2, 2], "lengthFt": 7, "widthFt": 4, "heightFt": 5, "minTons": 1, "maxTons": 2, "goods": ["fmcg"], "bodies": ["open"], "priceBand": 2}'
        ']}';
    final problems = VehicleCatalog.validate(bad).join('\n');
    for (final p in ['lower_snake_case', 'unknown group', 'axles', 'payload', 'priceBand', 'goods', 'bodies', 'height', 'wider than long', 'duplicate id']) {
      expect(problems, contains(p));
    }
  });

  test('every body type is one the vehicle form already knows', () {
    for (final v in all) {
      expect(BodyType.all, containsAll(v.bodies), reason: v.id);
    }
  });

  testWidgets('the catalog loads from the app bundle', (t) async {
    final list = await t.runAsync(() => VehicleCatalog.load(bundle: rootBundle));
    expect(list, hasLength(27));
  });

  test('docs/VEHICLE_REVIEW.csv has one row per vehicle with the same numbers (node tool/vehicle_review_csv.js --write)', () {
    final rows = File('docs/VEHICLE_REVIEW.csv').readAsLinesSync().skip(1).where((l) => l.trim().isNotEmpty).toList();
    expect(rows.length, all.length);
    for (final v in all) {
      final row = rows.firstWhere((r) => r.startsWith('${v.id},'), orElse: () => '');
      expect(row, isNotEmpty, reason: v.id);
      String n(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toString();
      expect(row, contains(',${v.axles.join('+')},${n(v.lengthFt)},${n(v.widthFt)},${n(v.heightFt)},${n(v.minTons)},${n(v.maxTons)},'), reason: v.id);
    }
  });
}
