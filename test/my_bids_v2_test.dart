import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/driver/my_offers_screen.dart';
import 'package:transport_app/driver/v2/my_bids_v2.dart';

import 'test_utils.dart';

/// U31: My bids with a chip per group, one card per bid, and the bid sheet for a change.
void main() {
  test('bidGroupOf puts every status in one of the four groups', () {
    expect(bidGroupOf(OfferStatus.pending), BidGroup.waiting);
    expect(bidGroupOf(OfferStatus.countered), BidGroup.countered);
    expect(bidGroupOf(OfferStatus.selected), BidGroup.selected);
    expect(bidGroupOf(OfferStatus.confirmed), BidGroup.selected);
    expect(bidGroupOf(OfferStatus.rejected), BidGroup.lost);
    expect(bidGroupOf(OfferStatus.withdrawn), BidGroup.lost);
    expect(bidGroupOf('something new'), BidGroup.waiting);
  });

  group('screen', () {
    late FakeFirebaseFirestore db;
    String? uid;
    late Load load;
    late Vehicle vehicle;

    setUp(() async {
      FeaturesService.reset();
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => uid);
      languageNotifier.value = AppLanguage.english;
      uid = 'customer1';
      final id = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 25000, pickupDate: DateTime(2030, 10, 5), notes: '');
      load = Load.fromDoc(await db.collection('loads').doc(id).get());
      uid = 'driver1';
      await db.collection('users').doc('driver1').set({'driverName': 'Ramesh'});
      final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC');
      vehicle = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
    });
    tearDown(FeaturesService.reset);

    Future<void> show(WidgetTester t) async {
      t.view.physicalSize = const Size(360 * 2, 900 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(theme: AppTheme.build(Brightness.light), home: MyOffersScreen(onOpenBooking: (_) {}))));
      await settle(t);
    }

    testWidgets('chips count the groups and filter; a pending bid opens the bid sheet to change it', (t) async {
      final id = (await t.runAsync(() => OfferService.send(load: load, vehicle: vehicle, pricePaise: 2500000)))!;
      await show(t);
      expect(find.text('Waiting (1)'), findsOneWidget);
      final row = find.descendant(of: find.byKey(const ValueKey('mbGroups')), matching: find.byType(Scrollable));
      await t.scrollUntilVisible(find.text('Selected (0)'), 100, scrollable: row);
      expect(find.text('Selected (0)'), findsOneWidget);
      expect(find.byKey(ValueKey('mbPrice_$id')), findsOneWidget);

      await t.ensureVisible(find.text('Selected (0)'));
      await t.pump();
      await t.tap(find.text('Selected (0)'));
      await settle(t);
      expect(find.text('Nothing here yet'), findsOneWidget);
      await t.drag(row, const Offset(600, 0));
      await t.pump();
      await t.tap(find.text('Waiting (1)'));
      await settle(t);
      expect(find.byKey(ValueKey('mbPrice_$id')), findsOneWidget);

      await t.tap(find.byKey(ValueKey('change_$id')));
      await settle(t);
      expect(find.byKey(const ValueKey('bsSend')), findsOneWidget);
      expect(find.byKey(const ValueKey('bsWithdraw')), findsOneWidget);
    });

    testWidgets('uiV2 off: the old list, without chips', (t) async {
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.uiV2: false});
      await t.runAsync(() => OfferService.send(load: load, vehicle: vehicle, pricePaise: 2500000));
      await show(t);
      expect(find.byKey(const ValueKey('mbGroups')), findsNothing);
      expect(find.text('Waiting'), findsNothing);
    });
  });
}
