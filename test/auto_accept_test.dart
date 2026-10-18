import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/dispatch/auto_accept_watcher.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/trust/public_trust.dart';

/// U14: the customer's auto-accept rule is applied by the client while the app is open.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late String loadId;
  final vehicles = <String, Vehicle>{};
  final trust = <String, PublicTrust>{
    'driver1': const PublicTrust(uid: 'driver1', trips: 50, rating: 4.6, ratingCount: 20, verified: true),
    'driver2': const PublicTrust(uid: 'driver2', trips: 90, rating: 4.9, ratingCount: 40, verified: true),
    'driver3': const PublicTrust(uid: 'driver3', trips: 3, rating: 3.2, ratingCount: 3, verified: false),
  };

  Future<void> post(AutoAccept? rule) async {
    uid = 'customer1';
    loadId = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null, pickupDate: DateTime(2030, 10, 5), notes: '', mode: LoadMode.bid, autoAccept: rule);
  }

  Future<Load> readLoad() async => Load.fromDoc(await db.collection('loads').doc(loadId).get());
  Future<List<Offer>> offers() async => [for (final d in (await db.collection('offers').get()).docs) Offer.fromDoc(d)];
  Future<String> status(String driver) async => Offer.fromDoc(await db.collection('offers').doc('${loadId}_$driver').get()).status;

  Future<void> bid(String driver, int paise) async {
    uid = driver;
    await OfferService.send(load: await readLoad(), vehicle: vehicles[driver]!, pricePaise: paise);
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    AutoAcceptWatcher.resetForTest();
    AutoAcceptWatcher.trustReader = (id) async => trust[id];
    for (final (driver, number) in [('driver1', 'MH12AB1234'), ('driver2', 'KA01CD5678'), ('driver3', 'GJ01EF9012')]) {
      uid = driver;
      await db.collection('users').doc(driver).set({'driverName': driver});
      final vid = await VehicleService.add(number: number, type: '14ft', capacity: 4, rcNumber: 'RC');
      vehicles[driver] = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
    }
  });

  Future<List<String>> run() async {
    uid = 'customer1';
    return AutoAcceptWatcher.evaluate([await readLoad()], await offers());
  }

  test('the cheapest bid that fits the rule is accepted and the others are closed', () async {
    await post(const AutoAccept(maxPaise: 2500000, minRating: 4.5, verifiedOnly: true));
    await bid('driver1', 2400000);
    await bid('driver2', 2300000);
    await bid('driver3', 2000000); // cheapest, but rated 3.2 and not verified
    expect(await run(), ['${loadId}_driver2']);
    expect(await status('driver2'), OfferStatus.selected);
    expect(await status('driver1'), OfferStatus.rejected);
    expect(await status('driver3'), OfferStatus.rejected);
  });

  test('nothing fits: nothing is accepted and every bid stays open', () async {
    await post(const AutoAccept(maxPaise: 1000000));
    await bid('driver1', 2400000);
    expect(await run(), isEmpty);
    expect(await status('driver1'), OfferStatus.pending);
  });

  test('a rating rule is not met when the rating is unknown', () async {
    await post(const AutoAccept(maxPaise: 9000000, minRating: 4));
    AutoAcceptWatcher.trustReader = (_) async => null;
    await bid('driver1', 2400000);
    expect(await run(), isEmpty);
  });

  test('no rule, a load that is not open, or a bid already chosen by hand: nothing happens', () async {
    await post(null);
    await bid('driver1', 2400000);
    expect(await run(), isEmpty);
    await post(const AutoAccept(maxPaise: 9000000));
    await bid('driver2', 2300000);
    uid = 'customer1';
    await OfferService.select((await offers()).firstWhere((o) => o.loadId == loadId));
    expect(await run(), isEmpty, reason: 'the customer already chose');
    await db.collection('loads').doc(loadId).update({'status': 'closed'});
    expect(await run(), isEmpty);
  });

  test('a second pass does not accept again and a failed bid is not tried in a loop', () async {
    await post(const AutoAccept(maxPaise: 9000000));
    await bid('driver1', 2400000);
    expect(await run(), hasLength(1));
    expect(await run(), isEmpty);
  });

  test('only the owner of the load runs the rule', () async {
    await post(const AutoAccept(maxPaise: 9000000));
    await bid('driver1', 2400000);
    uid = 'driver1';
    expect(await AutoAcceptWatcher.evaluate([await readLoad()], await offers()), isEmpty);
  });
}
