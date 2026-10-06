import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_offers_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/location/geohash.dart';
import 'package:transport_app/core/offers/offers_switch.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/offers_switch_service.dart';
import 'package:transport_app/core/services/reminder_service.dart';
import 'package:transport_app/core/services/ttl_cache.dart';
import 'package:transport_app/customer/offers_section.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
    languageNotifier.value = AppLanguage.english;
    OffersSwitchService.reset();
  });
  tearDown(OffersSwitchService.reset);

  group('offers switch', () {
    test('everything is OFF when the document or a field is missing', () {
      expect(OffersSwitch.fromMap(null).any, isFalse);
      expect(OffersSwitch.fromMap({'referralBonusPaise': 10000}).any, isFalse);
      final s = OffersSwitch.fromMap({'promoEnabled': true, 'creditsEnabled': 'yes'});
      expect(s.promo, isTrue);
      expect(s.credits, isFalse, reason: 'only a real true turns it on');
      expect(s.referral, isFalse);
    });

    test('round trip and copyWith', () {
      const s = OffersSwitch(promo: true);
      expect(OffersSwitch.fromMap(s.toMap()), s);
      expect(s.copyWith(referral: true).referral, isTrue);
      expect(s.copyWith(referral: true).promo, isTrue);
    });

    test('service reads config/offers, keeps the referral bonus on save', () async {
      await db.collection('config').doc('offers').set({'referralBonusPaise': 25000, 'promoEnabled': true});
      await OffersSwitchService.refresh(force: true);
      expect(OffersSwitchService.current, const OffersSwitch(promo: true));
      await OffersSwitchService.save(const OffersSwitch(promo: true, credits: true));
      final d = (await db.collection('config').doc('offers').get()).data()!;
      expect(d['referralBonusPaise'], 25000);
      expect(d['creditsEnabled'], isTrue);
    });

    test('a failed read keeps OFF', () async {
      Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => null);
      await OffersSwitchService.refresh(force: true);
      expect(OffersSwitchService.current.any, isFalse);
    });
  });

  group('ttl cache', () {
    test('fetches once inside the ttl, again after it, and on force', () async {
      var now = DateTime(2026, 10, 6, 12);
      final cache = TtlCache(const Duration(minutes: 15), clock: () => now);
      var calls = 0;
      Future<void> fetch() async => calls++;
      expect(await cache.run(fetch), isTrue);
      expect(await cache.run(fetch), isFalse);
      now = now.add(const Duration(minutes: 14));
      expect(await cache.run(fetch), isFalse);
      now = now.add(const Duration(minutes: 2));
      expect(await cache.run(fetch), isTrue);
      expect(await cache.run(fetch, force: true), isTrue);
      expect(calls, 3);
    });

    test('a failing fetch is not remembered', () async {
      final cache = TtlCache(const Duration(minutes: 5));
      await expectLater(cache.run(() async => throw StateError('offline')), throwsStateError);
      expect(cache.fresh, isFalse);
    });
  });

  group('nearby cells', () {
    const delhi = (lat: 28.6139, lng: 77.2090);

    test('four cells, including the one the point is in, all of the same length', () {
      for (final p in [4, 5, 3]) {
        final cells = geohashCoreCells(delhi.lat, delhi.lng, p);
        expect(cells.length, lessThanOrEqualTo(4));
        expect(cells.length, greaterThanOrEqualTo(2));
        expect(cells, contains(geohashEncode(delhi.lat, delhi.lng, precision: p)));
        expect(cells.every((c) => c.length == p), isTrue);
      }
    });

    test('a point near the east edge reaches the cell to the east, not the west', () {
      final size = geohashCellSize(4);
      // Just inside the east edge of its cell.
      const lat = 10.0;
      final lng = (77.0 / size.lng).floor() * size.lng + size.lng * 0.95;
      final cells = geohashCoreCells(lat, lng, 4);
      expect(cells, contains(geohashEncode(lat, lng + size.lng * 0.1, precision: 4)));
      expect(cells, isNot(contains(geohashEncode(lat, lng - size.lng * 1.0, precision: 4))));
    });

    test('the poles and the date line do not throw', () {
      expect(geohashCoreCells(89.99, 179.99, 3), isNotEmpty);
      expect(geohashCoreCells(-89.99, -179.99, 3), isNotEmpty);
    });
  });

  group('reminders cost', () {
    test('the clock tick is 5 minutes', () => expect(ReminderService.tick, const Duration(minutes: 5)));
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: w)));
      await settle(tester);
    }

    testWidgets('the offers block is hidden while all switches are off, shown per switch', (tester) async {
      await pump(tester, Scaffold(body: OffersSection(total: 100000, onChanged: (_) {})));
      expect(find.byKey(const ValueKey('promoCode')), findsNothing);
      OffersSwitchService.notifier.value = const OffersSwitch(promo: true);
      await tester.pump();
      expect(find.byKey(const ValueKey('promoCode')), findsOneWidget);
      OffersSwitchService.notifier.value = const OffersSwitch(credits: true);
      await tester.pump();
      expect(find.byKey(const ValueKey('promoCode')), findsNothing);
      expect(find.text(T.get('offersRecordNote', AppLanguage.english)), findsOneWidget);
    });

    testWidgets('admin switches write config/offers', (tester) async {
      await db.collection('config').doc('offers').set({'referralBonusPaise': 10000});
      await pump(tester, const AdminOffersScreen());
      await tester.tap(find.byKey(const ValueKey('switchPromo')));
      await settle(tester);
      final d = (await db.collection('config').doc('offers').get()).data()!;
      expect(d['promoEnabled'], isTrue);
      expect(d['creditsEnabled'], isFalse);
      expect(d['referralBonusPaise'], 10000);
    });
  });
}
