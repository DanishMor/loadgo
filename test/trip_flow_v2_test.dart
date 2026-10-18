import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/driver/driver_trip_screen.dart';

import 'test_utils.dart';

/// U32: the driver's next step is one big card at the top of the trip page.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late String bookingId;

  setUp(() async {
    FeaturesService.reset();
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    uid = 'customer1';
    final loadId = await LoadService.post(pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: null, pickupDate: DateTime(2030, 10, 5), notes: '');
    uid = 'driver1';
    await db.collection('users').doc('driver1').set({'driverName': 'Ramesh', 'phone': '+919800000000'});
    await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).single;
    bookingId = await BookingService.accept(loadId: loadId, vehicle: vehicle);
  });
  tearDown(FeaturesService.reset);

  Future<void> show(WidgetTester t, {Brightness b = Brightness.light, double scale = 1, double width = 360}) async {
    t.view.physicalSize = Size(width * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        theme: AppTheme.build(b),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: DriverTripScreen(bookingId: bookingId),
      ),
    ));
    await settle(t);
  }

  testWidgets('step card on top: step 1 of 6 and one big button that moves the trip on', (t) async {
    await show(t);
    expect(find.byKey(const ValueKey('tfStep')), findsOneWidget);
    expect(find.text('Step 1 of 6'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('tfNext')));
    await settle(t);
    final b = await t.runAsync(() => db.collection('bookings').doc(bookingId).get());
    expect(b!.data()!['status'], 'driver_arriving');
    expect(find.text('Step 2 of 6'), findsOneWidget);
  });

  testWidgets('the pickup step says a photo and the pickup code will be asked; the last step warns about the delivery code', (t) async {
    await t.runAsync(() => db.collection('bookings').doc(bookingId).update({'status': 'loading'}));
    await show(t);
    expect(find.text('Step 3 of 6'), findsOneWidget);
    expect(find.byKey(const ValueKey('tfHint')), findsOneWidget);
    await t.runAsync(() => db.collection('bookings').doc(bookingId).update({'status': 'unloading'}));
    await settle(t);
    expect(find.text('Step 6 of 6'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
  });

  testWidgets('dark, 2.0x text: no overflow', (t) async {
    await show(t, b: Brightness.dark, scale: 2);
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('tfStep')), findsOneWidget);
  });

  testWidgets('uiV2 off: the old page without the step card', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.uiV2: false});
    // wider than a phone: an old card on the old page is not what this test is about
    await show(t, width: 600);
    expect(find.byKey(const ValueKey('tfStep')), findsNothing);
    await t.scrollUntilVisible(find.text('Start: going to pickup'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Start: going to pickup'), findsOneWidget);
  });
}
