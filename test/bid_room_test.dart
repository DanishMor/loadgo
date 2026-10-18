import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/dispatch/trust_lookup.dart';
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
import 'package:transport_app/core/trust/public_trust.dart';
import 'package:transport_app/customer/v2/bid_room_screen.dart';

/// U20: the Bid Room.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late String loadId;
  final vehicles = <String, Vehicle>{};

  Future<Load> readLoad() async => Load.fromDoc(await db.collection('loads').doc(loadId).get());

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    FeaturesService.reset();
    TrustLookup.reset();
    TrustLookup.reader = (id) async => const {
      'driver1': PublicTrust(uid: 'driver1', trips: 80, rating: 4.7, ratingCount: 30, verified: true),
      'driver2': PublicTrust(uid: 'driver2', trips: 12, rating: 4.1, ratingCount: 6),
      'driver3': PublicTrust(uid: 'driver3', trips: 200, rating: 4.9, ratingCount: 90, verified: true),
    }[id];
    languageNotifier.value = AppLanguage.english;
    for (final (driver, number, name) in [('driver1', 'MH12AB1234', 'Ramesh'), ('driver2', 'KA01CD5678', 'Suresh'), ('driver3', 'GJ01EF9012', 'Mahesh')]) {
      uid = driver;
      await db.collection('users').doc(driver).set({'driverName': name});
      final vid = await VehicleService.add(number: number, type: '14ft', capacity: 4, rcNumber: 'RC');
      vehicles[driver] = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
    }
    uid = 'customer1';
  });

  Future<void> post({LoadMode mode = LoadMode.bid}) async {
    uid = 'customer1';
    loadId = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 25000, pickupDate: DateTime(2030, 10, 5), notes: '', mode: mode);
  }

  Future<void> bid(String driver, int paise, {int? eta, int? km, BidNote? note}) async {
    uid = driver;
    final load = await readLoad();
    await OfferService.send(load: load, vehicle: vehicles[driver]!, pricePaise: paise, etaMinutes: eta, pickupKm: km, note: note);
    uid = 'customer1';
  }

  Widget host({double scale = 1.0, Brightness b = Brightness.light, AppLanguage lang = AppLanguage.english}) {
    languageNotifier.value = lang;
    return LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        theme: AppTheme.build(b),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: BidRoomScreen(loadId: loadId),
      ),
    );
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  void bigView(WidgetTester t) {
    t.view.physicalSize = const Size(800, 3600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('a bid load shows the route, the price, the window ring and every bid with tags; best price first', (t) async {
    bigView(t);
    await t.runAsync(() async {
      await post();
      await bid('driver1', 2400000, eta: 40, km: 12);
      await bid('driver2', 2200000, eta: 60, km: 3, note: BidNote.onTheWay);
      await bid('driver3', 2600000, eta: 20, km: 30);
    });
    await t.pumpWidget(host());
    await settle(t);
    expect(find.text('Bid room'), findsOneWidget);
    expect(find.byKey(const ValueKey('brRing')), findsOneWidget);
    expect(find.text('Bidding closes in'), findsOneWidget);
    expect(find.byKey(const ValueKey('brPrice')), findsOneWidget);
    final y = [for (final d in ['driver2', 'driver1', 'driver3']) t.getTopLeft(find.byKey(ValueKey('bid_${loadId}_$d'))).dy];
    expect(y[0], lessThan(y[1]));
    expect(y[1], lessThan(y[2]));
    expect(find.text('Best price'), findsWidgets);
    expect(find.text('I am on the way'), findsOneWidget);
    expect(find.text('Fastest'), findsWidgets);
  });

  testWidgets('the sort chips reorder the bids', (t) async {
    bigView(t);
    await t.runAsync(() async {
      await post();
      await bid('driver1', 2400000, eta: 40, km: 12);
      await bid('driver2', 2200000, eta: 60, km: 3);
      await bid('driver3', 2600000, eta: 20, km: 30);
    });
    await t.pumpWidget(host());
    await settle(t);
    double top(String d) => t.getTopLeft(find.byKey(ValueKey('bid_${loadId}_$d'))).dy;
    await t.tap(find.widgetWithText(ChoiceChip, 'Fastest'));
    await t.pump();
    expect(top('driver3'), lessThan(top('driver1')));
    expect(top('driver1'), lessThan(top('driver2')));
    await t.tap(find.widgetWithText(ChoiceChip, 'Top rated'));
    await t.pump();
    expect(top('driver3'), lessThan(top('driver1')));
    expect(top('driver1'), lessThan(top('driver2')));
    await t.tap(find.widgetWithText(ChoiceChip, 'Nearest'));
    await t.pump();
    expect(top('driver2'), lessThan(top('driver1')));
  });

  testWidgets('accept asks first, then selects that bid and closes the others', (t) async {
    bigView(t);
    await t.runAsync(() async {
      await post();
      await bid('driver1', 2400000);
      await bid('driver2', 2200000);
    });
    await t.pumpWidget(host());
    await settle(t);
    await t.tap(find.descendant(of: find.byKey(ValueKey('bid_${loadId}_driver2')), matching: find.byKey(const ValueKey('bidAccept'))));
    await t.pumpAndSettle();
    expect(find.textContaining('Accept the bid of'), findsOneWidget);
    await t.tap(find.text('Yes, accept'));
    await t.pump();
    await settle(t);
    Future<String> status(String d) async => Offer.fromDoc(await db.collection('offers').doc('${loadId}_$d').get()).status;
    expect(await t.runAsync(() => status('driver2')), OfferStatus.selected);
    expect(await t.runAsync(() => status('driver1')), OfferStatus.rejected);
    expect(find.text('Waiting for the driver to confirm.'), findsOneWidget);
  });

  testWidgets('counter once: the sheet takes a price, the driver sees it, the counter button goes away', (t) async {
    bigView(t);
    await t.runAsync(() async {
      await post();
      await bid('driver1', 2400000);
    });
    await t.pumpWidget(host());
    await settle(t);
    await t.tap(find.byKey(const ValueKey('bidCounter')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('counterField')), '21000');
    await t.tap(find.byKey(const ValueKey('counterSend')));
    await t.pumpAndSettle();
    await settle(t);
    final o = await t.runAsync(() async => Offer.fromDoc(await db.collection('offers').doc('${loadId}_driver1').get()));
    expect((o!.status, o.counterPaise), (OfferStatus.countered, 2100000));
    expect(find.byKey(const ValueKey('bidCounter')), findsNothing);
    expect(find.text('You countered. Waiting for the driver.'), findsOneWidget);
  });

  testWidgets('after the window with no bid the screen offers the four ways forward; raising the price changes the load', (t) async {
    bigView(t);
    await t.runAsync(() async {
      await post();
      await db.collection('loads').doc(loadId).update({'bidWindowEnds': Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 1)))});
    });
    await t.pumpWidget(host());
    await settle(t);
    expect(find.text('Bidding is closed.'), findsOneWidget);
    expect(find.text('What next?'), findsOneWidget);
    for (final k in ['raisePrice', 'moreTime', 'goInstant', 'schedule']) {
      expect(find.byKey(ValueKey('brSuggest_$k')), findsOneWidget, reason: k);
    }
    await t.tap(find.byKey(const ValueKey('brSuggest_raisePrice')));
    await settle(t);
    expect((await t.runAsync(readLoad))!.budget, 27500);
    await t.tap(find.byKey(const ValueKey('brSuggest_goInstant')));
    await settle(t);
    expect((await t.runAsync(readLoad))!.mode, LoadMode.instant);
  });

  testWidgets('more time pushes the window forward and brings the ring back', (t) async {
    bigView(t);
    await t.runAsync(() async {
      await post();
      await db.collection('loads').doc(loadId).update({'bidWindowEnds': Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 1)))});
    });
    await t.pumpWidget(host());
    await settle(t);
    await t.tap(find.byKey(const ValueKey('brSuggest_moreTime')));
    await settle(t);
    expect(find.byKey(const ValueKey('brRing')), findsOneWidget);
    expect(find.text('What next?'), findsNothing);
  });

  testWidgets('with dispatchV2 off an instant load shows the old waiting line and its offers in the same cards', (t) async {
    bigView(t);
    await t.runAsync(() async {
      await post(mode: LoadMode.instant);
    });
    await t.pumpWidget(host());
    await settle(t);
    expect(find.byKey(const ValueKey('brWaiting')), findsOneWidget);
    expect(find.byKey(const ValueKey('brAuto')), findsNothing, reason: 'auto-accept belongs to dispatchV2');
    await t.runAsync(() async {
      await bid('driver1', 2400000);
    });
    await settle(t);
    expect(find.byKey(ValueKey('bid_${loadId}_driver1')), findsOneWidget);
    expect(find.byKey(const ValueKey('brWaiting')), findsNothing);
  });

  testWidgets('with dispatchV2 on the auto-accept rule can be set and turned off', (t) async {
    bigView(t);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.dispatchV2: true});
    await t.runAsync(() async {
      await post();
    });
    await t.pumpWidget(host());
    await settle(t);
    await t.tap(find.byKey(const ValueKey('brAuto')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('autoMax')), '24000');
    await t.tap(find.widgetWithText(ChoiceChip, '4+'));
    await t.tap(find.byKey(const ValueKey('autoVerified')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('autoSave')));
    await t.pumpAndSettle();
    await settle(t);
    final l = (await t.runAsync(readLoad))!;
    expect((l.autoAccept!.maxPaise, l.autoAccept!.minRating, l.autoAccept!.verifiedOnly), (2400000, 4.0, true));
    expect(find.textContaining('Auto-accept is on'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('brAuto')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('autoOff')));
    await t.pumpAndSettle();
    await settle(t);
    expect((await t.runAsync(readLoad))!.autoAccept, isNull);
  });

  testWidgets('a bad auto-accept price is refused in the sheet', (t) async {
    bigView(t);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.dispatchV2: true});
    await t.runAsync(() async {
      await post();
    });
    await t.pumpWidget(host());
    await settle(t);
    await t.tap(find.byKey(const ValueKey('brAuto')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('autoMax')), '0');
    await t.tap(find.byKey(const ValueKey('autoSave')));
    await t.pumpAndSettle();
    expect(find.text('Type your price.'), findsOneWidget);
    expect((await t.runAsync(readLoad))!.autoAccept, isNull);
  });

  testWidgets('a taken load shows the driver is confirmed and opens the trip; a missing load says it is closed', (t) async {
    bigView(t);
    await t.runAsync(() async {
      await post();
      await db.collection('loads').doc(loadId).update({'status': 'matched', 'bookingId': 'B1', 'driverId': 'driver1'});
    });
    await t.pumpWidget(host());
    await settle(t);
    expect(find.byKey(const ValueKey('brFound')), findsOneWidget);
    expect(find.byKey(const ValueKey('brTrack')), findsOneWidget);
    loadId = 'does-not-exist';
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host());
    await settle(t);
    expect(find.text('This load is closed.'), findsWidgets);
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.urdu]) {
    for (final b in Brightness.values) {
      testWidgets('fits 360x640 at 2.0x text with bids: ${lang.name} ${b.name}', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.runAsync(() async {
          await post();
          await bid('driver1', 2400000, eta: 40, km: 12, note: BidNote.flexibleTime);
          await bid('driver2', 2200000, eta: 60, km: 3);
        });
        await t.pumpWidget(host(scale: 2.0, b: b, lang: lang));
        await settle(t);
        expect(t.takeException(), isNull);
      });
    }
  }
}
