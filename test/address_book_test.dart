import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/repeat.dart';
import 'package:transport_app/core/models/saved_place.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/repeat_service.dart';
import 'package:transport_app/core/services/saved_place_service.dart';
import 'package:transport_app/customer/driver_trust_row.dart';
import 'package:transport_app/customer/saved_place_picker.dart';

import 'test_utils.dart';

/// MASTER-6 Task 19: billing details per address, favourite transporters.
void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
  });

  const gst = '27ABCDE1234F1Z5';

  test('a place keeps its billing details; a bad GSTIN is refused; billing text lists name, GSTIN, address', () async {
    final id = await SavedPlaceService.add(label: 'office', name: 'Head office', address: 'Andheri, Mumbai', legalName: ' Acme Pvt Ltd ', gstin: gst.toLowerCase());
    final p = SavedPlace.fromDoc(await db.collection('users').doc('c1').collection('saved_places').doc(id).get());
    expect((p.legalName, p.gstin, p.hasBilling), ('Acme Pvt Ltd', gst, true));
    expect(p.billingText(), 'Bill to: Acme Pvt Ltd\nGSTIN: $gst\nAddress: Andheri, Mumbai');
    await expectLater(SavedPlaceService.add(label: 'office', name: 'x', address: 'yy', gstin: '123'), throwsA(isA<InvalidGstinException>()));
    final plain = await SavedPlaceService.add(label: 'home', name: 'Home', address: 'Pune');
    final raw = (await db.collection('users').doc('c1').collection('saved_places').doc(plain).get()).data()!;
    expect(raw.containsKey('gstin'), isFalse);
    expect(SavedPlace.fromDoc(await db.collection('users').doc('c1').collection('saved_places').doc(plain).get()).hasBilling, isFalse);
  });

  testWidgets('the dialog rejects a bad GSTIN and the sheet shows it and copies the billing text', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => pickSavedPlace(c), child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('addSavedPlace')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('placeName')), 'Plant');
    await tester.enterText(find.byKey(const ValueKey('placeAddress')), 'MIDC Pune');
    await tester.enterText(find.byKey(const ValueKey('placeGstin')), 'BAD');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.textContaining('15-character'), findsOneWidget);
    expect((await db.collection('users').doc('c1').collection('saved_places').get()).docs, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('placeGstin')), gst);
    await tester.enterText(find.byKey(const ValueKey('placeLegalName')), 'Plant Foods Ltd');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.textContaining('GSTIN $gst'), findsOneWidget);
    final id = (await db.collection('users').doc('c1').collection('saved_places').get()).docs.single.id;
    await tester.tap(find.byKey(ValueKey('copyBilling_$id')));
    await settle(tester);
    expect(copied, contains('Bill to: Plant Foods Ltd'));
    expect(copied, contains('GSTIN: $gst'));
  });

  Booking trip({required String driver, String? owner}) => Booking(
        id: 'b1', loadId: 'b1', driverId: driver, vehicleId: 'v', customerId: 'c1', status: 'delivered', pickup: 'A', drop: 'B', cargoType: 'x', weight: 1,
        vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1', driverName: 'Acme Roadways', driverPhone: '1',
        timeline: const {}, fleetOwnerId: owner,
      );

  testWidgets('a trip a company took with its own fleet adds a favourite transporter; a plain driver a favourite driver', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: DriverTrustRow(booking: trip(driver: 'o1', owner: 'o1'))))));
    expect(find.text('Favourite this transporter'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('addFavourite')));
    await settle(tester);
    var fav = (await db.collection('users').doc('c1').collection('favourite_drivers').doc('o1').get()).data()!;
    expect(fav['kind'], 'transporter');
    expect(FavouriteDriver.fromDoc('o1', fav).isTransporter, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: DriverTrustRow(booking: trip(driver: 'd9', owner: 'o1'))))));
    expect(find.text('Favourite this transporter'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('addFavourite')));
    await settle(tester);
    fav = (await db.collection('users').doc('c1').collection('favourite_drivers').doc('d9').get()).data()!;
    expect(fav.containsKey('kind'), isFalse);
    expect(FavouriteDriver.fromDoc('d9', fav).kind, 'driver');
    expect((await RepeatService.favouriteIds()).toSet(), {'o1', 'd9'});
  });
}
