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
import 'package:transport_app/driver/driver_trip_screen.dart';

import 'test_utils.dart';

/// U43: the whole driver trip page, top to bottom, on a 360 px phone: nothing overflows, with the new step card and without.
void main() {
  for (final v2 in [true, false]) {
    testWidgets('driver trip page scrolled to the end at 360 px, uiV2 ${v2 ? 'on' : 'off'}', (t) async {
      final db = FakeFirebaseFirestore();
      String? uid = 'customer1';
      Backend.useFakes(db: db, uid: () => uid);
      languageNotifier.value = AppLanguage.english;
      FeaturesService.notifier.value = Features(flags: {FeatureKey.uiV2: v2});
      addTearDown(FeaturesService.reset);
      final loadId = await LoadService.post(pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: null, pickupDate: DateTime(2030, 10, 5), notes: '');
      uid = 'driver1';
      await db.collection('users').doc('driver1').set({'driverName': 'Ramesh', 'phone': '+919800000000'});
      await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
      final id = await BookingService.accept(loadId: loadId, vehicle: (await VehicleService.fetchMyActive()).single);
      t.view.physicalSize = const Size(720, 1280);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: DriverTripScreen(bookingId: id))));
      await settle(t);
      for (var i = 0; i < 12; i++) {
        expect(t.takeException(), isNull, reason: 'after $i screens down');
        await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await settle(t);
      }
      expect(t.takeException(), isNull);
    });
  }
}
