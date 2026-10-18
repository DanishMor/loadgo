// ignore_for_file: invalid_use_of_visible_for_testing_member
// Draws the new UX v2 screens to PNG with the real fonts (see tool/render_kit_test.dart):
//   flutter test tool/render_screens_test.dart            -> build/ux_png
// It builds no app and opens no emulator. Screens get fake data; nothing is sent anywhere.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/dispatch/trust_lookup.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/trust/public_trust.dart';
import 'package:transport_app/customer/v2/bid_room_screen.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/customer/v2/booking_wizard_model.dart';
import 'package:transport_app/customer/v2/booking_wizard_screen.dart';

import 'render_kit_test.dart' as r;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'customer1');
  });

  testWidgets('draw the booking wizard', (t) async {
    await t.runAsync(r.loadFonts);
    const full = WizardDraft(pickup: 'Delhi', drop: 'Jaipur', cargo: 'FMCG', weightTons: 3, vehicleType: '14ft');
    for (var step = 0; step < 5; step++) {
      final f = await r.renderPage(t, 'wizard_step${step + 1}_en', BookWizardScreen(initial: full.copyWith(step: step), bidAvailable: true));
      expect(f.lengthSync(), greaterThan(2000));
    }
    await r.renderPage(t, 'wizard_step4_hi_dark_1.3x', BookWizardScreen(initial: full.copyWith(step: 3), bidAvailable: true), lang: AppLanguage.hindi, b: Brightness.dark, scale: 1.3);
    await r.renderPage(t, 'wizard_step3_ur_rtl', BookWizardScreen(initial: full.copyWith(step: 2)), lang: AppLanguage.urdu);
  });

  testWidgets('draw the bid room', (t) async {
    await t.runAsync(r.loadFonts);
    final db = FakeFirebaseFirestore();
    String? uid = 'customer1';
    Backend.useFakes(db: db, uid: () => uid);
    TrustLookup.reader = (id) async => const {
      'driver1': PublicTrust(uid: 'driver1', trips: 80, rating: 4.7, ratingCount: 30, verified: true),
      'driver2': PublicTrust(uid: 'driver2', trips: 12, rating: 4.1, ratingCount: 6),
    }[id];
    late String loadId;
    await t.runAsync(() async {
      loadId = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 25000, pickupDate: DateTime(2030, 10, 5), notes: '', mode: LoadMode.bid);
      for (final (d, n, name, price, eta, km) in [('driver1', 'MH12AB1234', 'Ramesh Kumar', 2400000, 40, 12), ('driver2', 'KA01CD5678', 'Suresh Patel', 2200000, 60, 3)]) {
        uid = d;
        await db.collection('users').doc(d).set({'driverName': name});
        final vid = await VehicleService.add(number: n, type: '14ft', capacity: 4, rcNumber: 'RC');
        final v = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
        final load = Load.fromDoc(await db.collection('loads').doc(loadId).get());
        await OfferService.send(load: load, vehicle: v, pricePaise: price, etaMinutes: eta, pickupKm: km);
      }
      uid = 'customer1';
    });
    await r.renderPage(t, 'bidroom_en', BidRoomScreen(loadId: loadId), settle: false);
    await r.renderPage(t, 'bidroom_hi_dark', BidRoomScreen(loadId: loadId), settle: false, lang: AppLanguage.hindi, b: Brightness.dark);
  });
}
