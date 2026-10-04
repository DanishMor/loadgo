import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/vehicle_type.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/vehicle_type_service.dart';
import 'package:transport_app/core/widgets/logistics_labels.dart';
import 'package:transport_app/core/l10n/l10n.dart';
void main() {
  tearDown(VehicleTypeService.reset);

  test('fallback list covers every roadmap type with sane ranges', () {
    final ids = defaultVehicleTypes.map((t) => t.id).toSet();
    for (final id in ['Bike', 'Scooter', 'EV 2W', '3-Wheeler', 'Mini', '14ft', '17ft', '19ft', '20ft', '22ft', '24ft',
        '32ft', 'Container', 'Trailer', 'Open body']) {
      expect(ids, contains(id));
    }
    for (final t in defaultVehicleTypes) {
      expect(t.maxTons, greaterThan(t.minTons), reason: t.id);
      if (t.labelKey != null) expect(T.data.containsKey(t.labelKey), isTrue, reason: t.labelKey);
    }
  });

  test('refresh reads config/vehicle_types; bad config falls back', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    await VehicleTypeService.refresh();
    expect(VehicleTypeService.types.length, defaultVehicleTypes.length, reason: 'missing doc -> fallback');

    await db.collection('config').doc('vehicle_types').set({
      'types': [
        {'id': 'Mini', 'name': 'Mini truck', 'labelKey': 'vtMini', 'minTons': 0.75, 'maxTons': 1.5, 'category': 'lcv'},
        {'id': 'Tempo', 'name': 'Tempo', 'minTons': 1, 'maxTons': 3, 'category': 'lcv'},
        {'id': 'Old', 'name': 'Old', 'minTons': 1, 'maxTons': 3, 'category': 'lcv', 'active': false},
      ],
    });
    await VehicleTypeService.refresh();
    expect(VehicleTypeService.ids, ['Mini', 'Tempo']);
    expect(VehicleTypeService.byId('Old'), isNotNull, reason: 'inactive types still resolve for old data');
    expect(VehicleTypeService.byId('Mini')!.fits(2), isFalse);

    expect(VehicleTypeService.parse({'types': []}).length, defaultVehicleTypes.length);
    expect(VehicleTypeService.parse({'types': 'oops'}).length, defaultVehicleTypes.length);
  });

  test('save writes the admin config document', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    await VehicleTypeService.save(defaultVehicleTypes.take(2).toList());
    final d = (await db.collection('config').doc('vehicle_types').get()).data()!;
    expect((d['types'] as List).length, 2);
    expect(VehicleTypeService.parse(d).first.id, 'Bike');
  });

  testWidgets('labels are translated; feet types use the pattern; unknown ids show the name', (tester) async {
    late BuildContext ctx;
    languageNotifier.value = AppLanguage.hindi;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    ));
    expect(vehicleTypeLabel(ctx, 'Mini'), 'मिनी ट्रक');
    expect(vehicleTypeLabel(ctx, '17ft'), '17 फुट ट्रक');
    expect(vehicleTypeLabel(ctx, 'Hovercraft'), 'Hovercraft');
    languageNotifier.value = AppLanguage.english;
  });
}
