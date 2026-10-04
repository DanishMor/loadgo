import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/customer/load_offers_screen.dart';
import 'package:transport_app/driver/my_offers_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late Load load;
  final vehicles = <String, Vehicle>{};

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    uid = 'customer1';
    final id = await LoadService.post(
        pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null,
        pickupDate: DateTime(2026, 10, 5), notes: '');
    load = Load.fromDoc(await db.collection('loads').doc(id).get());
    for (final (driver, number) in [('driver1', 'MH12AB1234'), ('driver2', 'KA01CD5678')]) {
      uid = driver;
      await db.collection('users').doc(driver).set({'driverName': driver == 'driver1' ? 'Ramesh' : 'Suresh'});
      final vid = await VehicleService.add(number: number, type: '14ft', capacity: 4, rcNumber: 'RC');
      vehicles[driver] = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
    }
  });

  Future<Offer> offer(String id) async => Offer.fromDoc(await db.collection('offers').doc(id).get());

  Future<String> send(String driver, int paise) {
    uid = driver;
    return OfferService.send(load: load, vehicle: vehicles[driver]!, pricePaise: paise);
  }

  test('one offer per driver; own load and bad prices refused', () async {
    final id = await send('driver1', 2500000);
    expect(id, '${load.id}_driver1');
    final o = await offer(id);
    expect(o.pricePaise, 2500000);
    expect(o.originalPaise, 2500000);
    expect(o.driverName, 'Ramesh');
    expect(o.pickup, 'Delhi');
    await expectLater(send('driver1', 2400000), throwsA(isA<OfferExistsException>()));
    expect(() => send('driver2', 0), throwsArgumentError);
    uid = 'customer1';
    await expectLater(OfferService.send(load: load, vehicle: vehicles['driver1']!, pricePaise: 100), throwsA(isA<OfferStateException>()));
  });

  test('single counter, driver accepts it, customer selects, driver confirms -> booking', () async {
    final id = await send('driver1', 2500000);
    uid = 'customer1';
    await OfferService.counter(id, 2200000);
    expect((await offer(id)).status, OfferStatus.countered);
    await expectLater(OfferService.counter(id, 2000000), throwsA(isA<OfferStateException>()));

    uid = 'driver1';
    await OfferService.acceptCounter(id);
    var o = await offer(id);
    expect(o.status, OfferStatus.pending);
    expect(o.pricePaise, 2200000);
    expect(o.canCounter, isFalse, reason: 'counter already used');

    await expectLater(OfferService.confirm(o), throwsA(isA<OfferStateException>()), reason: 'not selected yet');
    uid = 'customer1';
    await OfferService.select(o);
    uid = 'driver1';
    final bookingId = await OfferService.confirm(await offer(id));
    final b = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect(b.agreedFarePaise, 2200000);
    expect(b.offerId, id);
    o = await offer(id);
    expect(o.status, OfferStatus.confirmed);
    expect(o.bookingId, bookingId);
    expect((await db.collection('loads').doc(load.id).get()).data()!['status'], LoadStatus.matched);
  });

  test('selecting another offer puts the previous one back to pending', () async {
    final a = await send('driver1', 2500000);
    final b = await send('driver2', 2300000);
    uid = 'customer1';
    await OfferService.select(await offer(a));
    await OfferService.select(await offer(b));
    expect((await offer(a)).status, OfferStatus.pending);
    expect((await offer(b)).status, OfferStatus.selected);
    final list = await OfferService.watchForLoad(load.id).first;
    expect(list.first.id, b, reason: 'cheapest open offer first');
  });

  test('withdraw and reject end the offer; other people cannot act on it', () async {
    final a = await send('driver1', 2500000);
    uid = 'driver2';
    await expectLater(OfferService.withdraw(a), throwsA(isA<OfferStateException>()));
    await expectLater(OfferService.reject(a), throwsA(isA<OfferStateException>()));
    uid = 'customer1';
    await OfferService.reject(a);
    expect((await offer(a)).status, OfferStatus.rejected);
    uid = 'driver1';
    await expectLater(OfferService.withdraw(a), throwsA(isA<OfferStateException>()));
  });

  Widget app(Widget home) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: home));

  testWidgets('customer screen: counter once, then select', (tester) async {
    final id = (await tester.runAsync(() => send('driver1', 2500000)))!;
    uid = 'customer1';
    await tester.pumpWidget(app(LoadOffersScreen(load: load, onOpenBooking: (_) {})));
    await settle(tester);
    expect(find.text('Ramesh'), findsOneWidget);
    expect(find.text('₹ 25,000'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('counter_$id')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('priceField')), '21000');
    await tester.tap(find.byKey(const ValueKey('priceSubmit')));
    await settle(tester);
    expect(find.text('Counter: ₹ 21,000'), findsOneWidget);
    expect(find.byKey(ValueKey('counter_$id')), findsNothing);
  });

  testWidgets('driver screen: accept counter then confirm opens the booking', (tester) async {
    final id = (await tester.runAsync(() => send('driver1', 2500000)))!;
    uid = 'customer1';
    await tester.runAsync(() => OfferService.counter(id, 2100000));
    uid = 'driver1';
    String? opened;
    await tester.pumpWidget(app(MyOffersScreen(onOpenBooking: (b) => opened = b)));
    await settle(tester);
    expect(find.text('Customer countered'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('acceptCounter_$id')));
    await settle(tester);
    expect(find.text('₹ 21,000'), findsOneWidget);

    uid = 'customer1';
    await tester.runAsync(() async => OfferService.select(await offer(id)));
    uid = 'driver1';
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('confirm_$id')));
    await settle(tester);
    expect(opened, isNotNull);
  });
}
