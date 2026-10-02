import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/features/vehicle/add_vehicle_screen.dart';

void main() {
  testWidgets('validates input and saves a vehicle', (tester) async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'driver1');

    await tester.pumpWidget(const MaterialApp(home: AddVehicleScreen()));

    // Empty submit shows validation errors and writes nothing.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('This field is required'), findsWidgets);
    expect((await db.collection('vehicles').get()).docs, isEmpty);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'MH12 AB 1234');
    await tester.enterText(fields.at(1), '9');
    await tester.enterText(fields.at(2), 'RC998877');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final docs = (await db.collection('vehicles').get()).docs;
    expect(docs, hasLength(1));
    expect(docs.single['number'], 'MH12AB1234');
    expect(docs.single['type'], 'Mini');
  });
}
