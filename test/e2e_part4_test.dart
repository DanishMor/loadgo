import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/bilty/lr_service.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/dispatch/auto_accept_watcher.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/dispatch/load_dispatch_service.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/trust/public_trust.dart';

/// U40: whole flows from the customer's post to the booking, through the services (the same calls the screens make).
/// Fake Firestore runs transactions one after the other; the real two-driver race is in the rules test U15.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  final vehicles = <String, Vehicle>{};

  Future<String> post({LoadMode mode = LoadMode.instant, AutoAccept? auto, num? budget = 25000}) async {
    uid = 'customer1';
    return LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: budget, pickupDate: DateTime(2030, 10, 5), notes: '', mode: mode, autoAccept: auto);
  }

  Future<Load> read(String id) async => Load.fromDoc(await db.collection('loads').doc(id).get());
  Future<Offer> offer(String id, String driver) async => Offer.fromDoc(await db.collection('offers').doc('${id}_$driver').get());

  Future<void> bid(String id, String driver, int paise) async {
    uid = driver;
    await OfferService.send(load: await read(id), vehicle: vehicles[driver]!, pricePaise: paise, etaMinutes: 30, pickupKm: 5);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    AutoAcceptWatcher.resetForTest();
    AutoAcceptWatcher.trustReader = (id) async => const PublicTrust(uid: 'x', trips: 60, rating: 4.8, ratingCount: 30, verified: true);
    for (final (d, n) in [('driver1', 'MH12AB1234'), ('driver2', 'KA01CD5678')]) {
      uid = d;
      await db.collection('users').doc(d).set({'driverName': d, 'phone': '+919800000000'});
      final vid = await VehicleService.add(number: n, type: '14ft', capacity: 4, rcNumber: 'RC');
      vehicles[d] = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
    }
  });

  test('instant booking: post, one driver accepts, the load is matched, the booking holds the customer and the driver', () async {
    final id = await post();
    uid = 'driver1';
    final bookingId = await BookingService.accept(loadId: id, vehicle: vehicles['driver1']!);
    final b = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect((b.customerId, b.driverId, b.status), ('customer1', 'driver1', BookingStatus.accepted));
    expect((await read(id)).status, LoadStatus.matched);
  });

  test('bid booking: two bids, the customer accepts the cheaper, the other is closed, the driver confirms, the booking is at that price', () async {
    final id = await post(mode: LoadMode.bid);
    await bid(id, 'driver1', 2400000);
    await bid(id, 'driver2', 2300000);
    uid = 'customer1';
    final all = [await offer(id, 'driver1'), await offer(id, 'driver2')];
    await OfferService.acceptBid(all[1], all);
    expect((await offer(id, 'driver2')).status, OfferStatus.selected);
    expect((await offer(id, 'driver1')).status, OfferStatus.rejected);
    uid = 'driver2';
    final bookingId = await OfferService.confirm(await offer(id, 'driver2'));
    final b = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect((b.driverId, b.agreedFarePaise), ('driver2', 2300000));
    expect((await read(id)).status, LoadStatus.matched);
  });

  test('auto-accept: a bid inside the rule is accepted without the customer, the driver confirms', () async {
    final id = await post(mode: LoadMode.bid, auto: const AutoAccept(maxPaise: 2500000, minRating: 4.5, verifiedOnly: true));
    await bid(id, 'driver1', 2400000);
    uid = 'customer1';
    final done = await AutoAcceptWatcher.evaluate([await read(id)], [await offer(id, 'driver1')]);
    expect(done, ['${id}_driver1']);
    expect((await offer(id, 'driver1')).status, OfferStatus.selected);
    uid = 'driver1';
    final bookingId = await OfferService.confirm(await offer(id, 'driver1'));
    expect((await db.collection('bookings').doc(bookingId).get()).exists, isTrue);
  });

  test('bid expiry: after the window nobody can bid; the customer extends it and a bid goes through', () async {
    final id = await post(mode: LoadMode.bid);
    await db.collection('loads').doc(id).update({'bidWindowEnds': Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 1)))});
    await expectLater(bid(id, 'driver1', 2400000), throwsA(isA<BidWindowClosedException>()));
    uid = 'customer1';
    final end = await LoadDispatchService.extendBidWindow(await read(id), minutes: 10);
    expect(end!.isAfter(DateTime.now()), isTrue);
    await bid(id, 'driver1', 2400000);
    expect((await offer(id, 'driver1')).status, OfferStatus.pending);
  });

  test('no bid: the window ends empty, the customer raises the price and extends the time, then a bid arrives', () async {
    final id = await post(mode: LoadMode.bid);
    await db.collection('loads').doc(id).update({'bidWindowEnds': Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 1)))});
    expect((await db.collection('offers').where('loadId', isEqualTo: id).get()).docs, isEmpty);
    uid = 'customer1';
    expect(await LoadDispatchService.raisePrice(await read(id), 10), 27500);
    await LoadDispatchService.extendBidWindow(await read(id), minutes: 10);
    await bid(id, 'driver2', 2600000);
    expect((await offer(id, 'driver2')).pricePaise, 2600000);
  });

  test('two drivers accept the same instant load: one booking, the second is told the load is gone', () async {
    final id = await post();
    uid = 'driver1';
    await BookingService.accept(loadId: id, vehicle: vehicles['driver1']!);
    uid = 'driver2';
    await expectLater(BookingService.accept(loadId: id, vehicle: vehicles['driver2']!), throwsA(isA<LoadUnavailableException>()));
    expect((await db.collection('bookings').get()).docs.length, 1);
  });

  test('counter offer: the customer counters once, the driver accepts the counter, the customer selects, the booking is at the counter price', () async {
    final id = await post(mode: LoadMode.bid);
    await bid(id, 'driver1', 2500000);
    uid = 'customer1';
    await OfferService.counter('${id}_driver1', 2200000);
    expect((await offer(id, 'driver1')).status, OfferStatus.countered);
    await expectLater(OfferService.counter('${id}_driver1', 2100000), throwsA(isA<OfferStateException>()), reason: 'a bid is countered once');
    uid = 'driver1';
    await OfferService.acceptCounter('${id}_driver1');
    final o = await offer(id, 'driver1');
    expect((o.status, o.pricePaise), (OfferStatus.pending, 2200000));
    uid = 'customer1';
    await OfferService.select(o);
    uid = 'driver1';
    final bookingId = await OfferService.confirm(await offer(id, 'driver1'));
    expect(Booking.fromDoc(await db.collection('bookings').doc(bookingId).get()).agreedFarePaise, 2200000);
  });

  test('bilty: after the booking the customer makes a bilty, it gets a number and the copies are found; a driver cannot make one', () async {
    final id = await post();
    uid = 'driver1';
    final bookingId = await BookingService.accept(loadId: id, vehicle: vehicles['driver1']!);
    final b = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    const draft = LrDraft(consignorName: 'A Traders', consigneeName: 'B Stores', goods: 'FMCG', packages: 40, weightTons: 2, freightPaise: 2500000, advancePaise: 0, marginPaise: 0, gstPaise: 0);
    uid = 'customer1';
    final lr = await LrService.issue(b, draft);
    expect(lr.lrNo, startsWith('CS-'));
    final bundle = await LrService.bundle(lr);
    expect(bundle, isNotNull);
    uid = 'driver1';
    await expectLater(LrService.issue(b, draft), throwsA(isA<LrException>()));
  });
}
