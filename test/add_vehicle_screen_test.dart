import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/features/vehicle/add_vehicle_screen.dart';

void main() {
  testWidgets('validates input and saves a vehicle', (tester) async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'driver1');

    await tester.pumpWidget(const MaterialApp(home: AddVehicleScreen()));

    // Empty submit shows validation errors and writes nothing.
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('This field is required'), findsWidgets);
    expect((await db.collection('vehicles').get()).docs, isEmpty);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'MH12 AB 1234');
    await tester.enterText(fields.at(1), '9');
    await tester.enterText(fields.at(2), 'RC998877');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final docs = (await db.collection('vehicles').get()).docs;
    expect(docs, hasLength(1));
    expect(docs.single['number'], 'MH12AB1234');
    expect(docs.single['type'], 'Mini');
  });

  testWidgets('edit mode prefills, picks an RC photo and saves it', (tester) async {
    final db = FakeFirebaseFirestore();
    final uploaded = <String>[];
    Backend.useFakes(
      db: db,
      uid: () => 'driver1',
      uploader: (path, bytes, type) async {
        uploaded.add(path);
        return 'https://firebasestorage.googleapis.com/fake/$path';
      },
    );
    await db.collection('vehicles').doc('v1').set({
      'ownerId': 'driver1', 'number': 'MH12AB1234', 'type': '14ft', 'capacity': 9, 'rcNumber': 'RC1234', 'status': 'active',
    });
    final vehicle = Vehicle.fromDoc(await db.collection('vehicles').doc('v1').get());
    // 1x1 transparent PNG so Image.memory can decode it.
    AddVehicleScreen.pickImage = (_) async => Uint8List.fromList(const [
          137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, //
          196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, //
          78, 68, 174, 66, 96, 130,
        ]);

    await tester.pumpWidget(MaterialApp(home: AddVehicleScreen(vehicle: vehicle)));
    expect(find.text('Edit Vehicle'), findsOneWidget);
    expect(find.text('MH12AB1234'), findsOneWidget);

    await tester.ensureVisible(find.text('Upload RC photo'));
    await tester.tap(find.text('Upload RC photo'));
    await tester.pumpAndSettle();
    expect(find.text('Change photo'), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(uploaded, ['vehicles/driver1/v1/rc.jpg']);
    expect((await db.collection('vehicles').doc('v1').get())['rcImageUrl'], contains('rc.jpg'));
  });
}
