import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/dispatch/bid_ranking.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/dispatch/load_dispatch_service.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/server_clock.dart';
import 'package:transport_app/core/services/vehicle_service.dart';

/// U13: bid mode: the window, bids with ETA and note, one edit, accept closes the rest, the no-bid advice, ranking and tags.
Offer o(String id, int price, {int? eta, int? km, String status = OfferStatus.pending, int? created, bool companyVerified = false}) => Offer(
      id: id,
      loadId: 'L1',
      driverId: id,
      customerId: 'c1',
      vehicleId: 'v',
      vehicleNumber: 'N',
      vehicleType: '14ft',
      driverName: id,
      pricePaise: price,
      originalPaise: price,
      status: status,
      etaMinutes: eta,
      pickupKm: km,
      createdAt: created == null ? null : Timestamp.fromMillisecondsSinceEpoch(created),
      companyVerified: companyVerified,
    );

void main() {
  group('ranking and tags', () {
    final a = BidView(o('a', 2500000, eta: 40, km: 12, created: 1), rating: 4.2);
    final b = BidView(o('b', 2200000, eta: 60, km: 3, created: 2), rating: 4.8, verified: true);
    final c = BidView(o('c', 2600000, eta: 20, km: 30, created: 3));

    List<String> ids(List<BidView> l) => [for (final v in l) v.offer.id];

    test('each chip orders by its own key; unknown values go last; ties keep the lower price then the earlier bid', () {
      expect(ids(BidRanking.sort([a, b, c], BidSort.bestPrice)), ['b', 'a', 'c']);
      expect(ids(BidRanking.sort([a, b, c], BidSort.nearest)), ['b', 'a', 'c']);
      expect(ids(BidRanking.sort([a, b, c], BidSort.topRated)), ['b', 'a', 'c']);
      expect(ids(BidRanking.sort([a, b, c], BidSort.fastest)), ['c', 'a', 'b']);
      final tieA = BidView(o('x', 100, eta: 10, created: 5)), tieB = BidView(o('y', 100, eta: 10, created: 4)), tieC = BidView(o('z', 90, eta: 10, created: 9));
      expect(ids(BidRanking.sort([tieA, tieB, tieC], BidSort.fastest)), ['z', 'y', 'x']);
    });

    test('tags go to the lowest price, the nearest, the best rating and the fastest; nothing for a single bid or equal bids', () {
      final t = BidRanking.tags([a, b, c]);
      expect(t['b'], {BidTagKind.bestPrice, BidTagKind.nearest, BidTagKind.topRated});
      expect(t['c'], {BidTagKind.fastest});
      expect(t['a'], isEmpty);
      expect(BidRanking.tags([a])['a'], isEmpty);
      final same = BidRanking.tags([BidView(o('p', 100, eta: 5, km: 5)), BidView(o('q', 100, eta: 5, km: 5))]);
      expect(same['p'], isEmpty);
      final tied = BidRanking.tags([BidView(o('p', 100)), BidView(o('q', 100)), BidView(o('r', 200))]);
      expect(tied['p'], {BidTagKind.bestPrice});
      expect(tied['q'], {BidTagKind.bestPrice});
      expect(tied['r'], isEmpty);
    });

    test('only pending bids are live', () {
      final l = BidRanking.live([a, BidView(o('d', 1, status: OfferStatus.withdrawn)), BidView(o('e', 1, status: OfferStatus.countered))]);
      expect(ids(l), ['a']);
    });

    test('auto-accept picks the cheapest bid the rule allows, or nothing', () {
      expect(BidRanking.autoAcceptPick([a, b, c], const AutoAccept(maxPaise: 2550000, minRating: 4.5))!.offer.id, 'b');
      expect(BidRanking.autoAcceptPick([a, b, c], const AutoAccept(maxPaise: 2550000, minRating: 4.0, verifiedOnly: true))!.offer.id, 'b');
      expect(BidRanking.autoAcceptPick([a, b, c], const AutoAccept(maxPaise: 2100000)), isNull);
      expect(BidRanking.autoAcceptPick([a, b, c], const AutoAccept(maxPaise: 9999999, minRating: 5)), isNull);
      expect(BidRanking.autoAcceptPick([a, b, c], null), isNull);
      expect(BidRanking.autoAcceptPick([BidView(o('w', 1000, companyVerified: true))], const AutoAccept(maxPaise: 2000, verifiedOnly: true)), isNotNull);
    });

    test('no bids: after the window the four ways forward, before it nothing', () {
      final now = DateTime(2030, 1, 1, 12);
      expect(BidSuggestions.whenNoBids(liveBids: 0, windowEnds: now.add(const Duration(minutes: 1)), now: now), isEmpty);
      expect(BidSuggestions.whenNoBids(liveBids: 2, windowEnds: now.subtract(const Duration(minutes: 1)), now: now), isEmpty);
      expect(BidSuggestions.whenNoBids(liveBids: 0, windowEnds: now.subtract(const Duration(seconds: 1)), now: now), NoBidSuggestion.values);
      expect(BidSuggestions.whenNoBids(liveBids: 0, windowEnds: null, now: now), NoBidSuggestion.values);
    });
  });

  group('service', () {
    late FakeFirebaseFirestore db;
    String? uid;
    late Load load;
    final vehicles = <String, Vehicle>{};

    Future<Load> readLoad() async => Load.fromDoc(await db.collection('loads').doc(load.id).get());
    Future<Offer> offer(String id) async => Offer.fromDoc(await db.collection('offers').doc(id).get());

    setUp(() async {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => uid);
      ServerClock.reset();
      uid = 'customer1';
      final id = await LoadService.post(
        pickup: 'Delhi',
        drop: 'Jaipur',
        cargoType: 'FMCG',
        weight: 2,
        vehicleType: '14ft',
        budget: null,
        pickupDate: DateTime(2030, 10, 5),
        notes: '',
        mode: LoadMode.bid,
      );
      load = Load.fromDoc(await db.collection('loads').doc(id).get());
      for (final (driver, number) in [('driver1', 'MH12AB1234'), ('driver2', 'KA01CD5678'), ('driver3', 'GJ01EF9012')]) {
        uid = driver;
        await db.collection('users').doc(driver).set({'driverName': driver});
        final vid = await VehicleService.add(number: number, type: '14ft', capacity: 4, rcNumber: 'RC');
        vehicles[driver] = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
      }
    });

    Future<String> bid(String driver, int paise, {int? eta, BidNote? note, int? km}) {
      uid = driver;
      return OfferService.send(load: load, vehicle: vehicles[driver]!, pricePaise: paise, etaMinutes: eta, note: note, pickupKm: km);
    }

    test('a bid carries ETA, distance and a note chip; bad values are refused', () async {
      final id = await bid('driver1', 2500000, eta: 25, note: BidNote.onTheWay, km: 8);
      final x = await offer(id);
      expect((x.etaMinutes, x.pickupKm, x.note, x.edited), (25, 8, BidNote.onTheWay, false));
      expect(() => bid('driver2', 100, eta: 0), throwsArgumentError);
      expect(() => bid('driver2', 100, eta: 1441), throwsArgumentError);
      expect(() => bid('driver2', 100, km: -1), throwsArgumentError);
    });

    test('after the window ends no new bid is taken (the old model has no window and still works)', () async {
      await db.collection('loads').doc(load.id).update({'bidWindowEnds': Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 1)))});
      load = await readLoad();
      await expectLater(bid('driver1', 2500000), throwsA(isA<BidWindowClosedException>()));
      // an instant load has no window
      uid = 'customer1';
      final plain = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null, pickupDate: DateTime(2030, 10, 5), notes: '');
      final l2 = Load.fromDoc(await db.collection('loads').doc(plain).get());
      uid = 'driver1';
      expect(await OfferService.send(load: l2, vehicle: vehicles['driver1']!, pricePaise: 2000000), isNotEmpty);
    });

    test('one edit: new price, ETA and note; the second edit, another driver and a closed window are refused', () async {
      final id = await bid('driver1', 2500000, eta: 30);
      uid = 'driver1';
      await OfferService.edit(await offer(id), pricePaise: 2300000, etaMinutes: 20, note: BidNote.flexibleTime);
      var x = await offer(id);
      expect((x.pricePaise, x.originalPaise, x.etaMinutes, x.note, x.edited), (2300000, 2500000, 20, BidNote.flexibleTime, true));
      await expectLater(OfferService.edit(x, pricePaise: 2200000), throwsA(isA<BidAlreadyEditedException>()));
      final id2 = await bid('driver2', 2600000);
      uid = 'driver3';
      await expectLater(OfferService.edit(await offer(id2), pricePaise: 2000000), throwsA(isA<OfferStateException>()));
      uid = 'driver2';
      await db.collection('loads').doc(load.id).update({'bidWindowEnds': Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 1)))});
      await expectLater(OfferService.edit(await offer(id2), pricePaise: 2000000), throwsA(isA<BidWindowClosedException>()));
    });

    test('an edit outside 30% to 300% of the estimate is refused', () async {
      await db.collection('loads').doc(load.id).update({'estimate': {'baseFare': 2000000}});
      load = await readLoad();
      final id = await bid('driver1', 2000000);
      uid = 'driver1';
      await expectLater(OfferService.edit(await offer(id), pricePaise: 500000), throwsA(isA<OfferOutOfRangeException>()));
      await expectLater(OfferService.edit(await offer(id), pricePaise: 6100000), throwsA(isA<OfferOutOfRangeException>()));
      await OfferService.edit(await offer(id), pricePaise: 6000000);
    });

    test('accepting one bid selects it and closes every other open bid; the driver then confirms and the booking is made', () async {
      final i1 = await bid('driver1', 2500000);
      final i2 = await bid('driver2', 2400000);
      final i3 = await bid('driver3', 2600000);
      uid = 'driver3';
      await OfferService.withdraw(i3);
      uid = 'customer1';
      await OfferService.acceptBid(await offer(i2), [await offer(i1), await offer(i2), await offer(i3)]);
      expect((await offer(i2)).status, OfferStatus.selected);
      expect((await offer(i1)).status, OfferStatus.rejected);
      expect((await offer(i3)).status, OfferStatus.withdrawn, reason: 'a withdrawn bid stays withdrawn');
      uid = 'driver1';
      await expectLater(OfferService.edit(await offer(i1), pricePaise: 100), throwsA(isA<OfferStateException>()));
      uid = 'driver2';
      final bookingId = await OfferService.confirm(await offer(i2));
      final booking = (await db.collection('bookings').doc(bookingId).get()).data()!;
      expect(booking['agreedFarePaise'], 2400000);
      expect((await offer(i2)).status, OfferStatus.confirmed);
    });

    test('only the customer of the load can accept a bid, and a bid that is not pending cannot be accepted', () async {
      final i1 = await bid('driver1', 2500000);
      uid = 'driver2';
      await expectLater(OfferService.acceptBid(await offer(i1), const []), throwsA(isA<OfferStateException>()));
      uid = 'customer1';
      await OfferService.reject(i1);
      await expectLater(OfferService.acceptBid(await offer(i1), const []), throwsA(isA<OfferStateException>()));
    });

    test('with no bid the customer can go instant; the load keeps its window data and is still open', () async {
      uid = 'customer1';
      expect(await LoadDispatchService.switchToInstant(await readLoad()), isTrue);
      final l = await readLoad();
      expect((l.mode, l.isOpen), (LoadMode.instant, true));
      expect(await LoadDispatchService.switchToInstant(l), isFalse, reason: 'already instant');
      uid = 'driver1';
      expect(await LoadDispatchService.switchToInstant(l), isFalse);
    });
  });
}
