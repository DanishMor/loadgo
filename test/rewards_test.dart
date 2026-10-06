import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_offers_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/offers/offers_switch.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/services/offers_switch_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/rewards_service.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/customer/offers_screen.dart';
import 'package:transport_app/customer/offers_section.dart';

import 'test_utils.dart';

Promo promo({
  String code = 'SAVE10',
  String type = Promo.percent,
  int value = 10,
  int max = 0,
  int min = 0,
  DateTime? expires,
  int limit = 100,
  int perUser = 1,
  bool active = true,
}) =>
    Promo(
      code: code, type: type, value: value, maxDiscountPaise: max, minOrderPaise: min,
      expiresAt: expires ?? DateTime(2030), usageLimit: limit, perUserLimit: perUser, active: active,
    );

void main() {
  late FakeFirebaseFirestore db;
  String uid = 'c1';

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'c1';
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    OffersSwitchService.notifier.value = const OffersSwitch(promo: true, credits: true, referral: true);
  });
  tearDown(OffersSwitchService.reset);

  group('promo maths', () {
    test('percent rounds down, is capped, and never exceeds the order', () {
      expect(promo(value: 10).discountFor(99999), 9999);
      expect(promo(value: 10, max: 5000).discountFor(100000), 5000);
      expect(promo(value: 100).discountFor(7000), 7000);
      expect(promo(type: Promo.flat, value: 20000).discountFor(15000), 15000);
      expect(promo(type: Promo.flat, value: 20000, max: 10000).discountFor(100000), 10000);
    });

    test('problems: switched off, expired, below the minimum order', () {
      final now = DateTime(2026, 10, 4);
      expect(promo(active: false).problemFor(1000, now), PromoProblem.inactive);
      expect(promo(expires: DateTime(2026, 10, 4)).problemFor(1000, now), PromoProblem.expired);
      expect(promo(min: 50000).problemFor(49999, now), PromoProblem.belowMinimum);
      expect(promo(min: 50000).problemFor(50000, now), isNull);
    });

    test('payable and credits to spend', () {
      final p = promo(value: 10);
      expect(payableAfterOffers(total: 100000, promo: p), 90000);
      expect(payableAfterOffers(total: 100000, promo: p, creditsBalance: 30000, useCredits: true), 60000);
      expect(payableAfterOffers(total: 100000, promo: p, creditsBalance: 500000, useCredits: true), 0);
      expect(creditsToSpend(total: 100000, promo: p, creditsBalance: 500000, useCredits: true), 90000);
      expect(creditsToSpend(total: 100000, creditsBalance: 500000, useCredits: false), 0);
    });
  });

  group('reserve and redeem', () {
    Future<void> seedPromo(Promo p) => RewardsService.savePromo(p);

    test('a valid code gets a free slot and use number; code is case-insensitive', () async {
      await seedPromo(promo(limit: 5));
      final app = await RewardsService.reserve(' save10 ', 50000);
      expect(app.discountPaise, 5000);
      expect(app.slot, inInclusiveRange(1, 5));
      expect(app.use, 1);
    });

    test('refuses unknown, switched-off, expired and too-small orders', () async {
      await seedPromo(promo(code: 'OFF', active: false));
      await seedPromo(promo(code: 'OLD', expires: DateTime(2020)));
      await seedPromo(promo(code: 'BIG', min: 100000));
      Future<PromoProblem?> problem(String c, int total) async {
        try {
          await RewardsService.reserve(c, total);
          return null;
        } on PromoException catch (e) {
          return e.problem;
        }
      }

      expect(await problem('NOPE', 1000), PromoProblem.unknown);
      expect(await problem('OFF', 1000), PromoProblem.inactive);
      expect(await problem('OLD', 1000), PromoProblem.expired);
      expect(await problem('BIG', 99999), PromoProblem.belowMinimum);
      expect(await problem('BIG', 100000), isNull);
    });

    Future<String> postWith(PromoApplication app, {int credits = 0}) => LoadService.post(
          pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null,
          pickupDate: DateTime(2026, 10, 5), notes: '',
          estimate: FareCalculator.calculate(rule: const PricingRule(baseFare: 50000, perKm: 0, minimumFare: 0), distanceKm: 0),
          promo: app, creditsUsedPaise: credits,
        );

    test('posting with a promo records the slot, the per-user use and the discount on the load', () async {
      await seedPromo(promo(limit: 3));
      final app = await RewardsService.reserve('SAVE10', 50000);
      final id = await postWith(app);
      final load = Load.fromDoc(await db.collection('loads').doc(id).get());
      expect(load.promoCode, 'SAVE10');
      expect(load.promoDiscountPaise, 5000);
      expect((await db.collection('promos').doc('SAVE10').collection('slots').doc('${app.slot}').get()).data()!['loadId'], id);
      expect((await db.collection('promos').doc('SAVE10').collection('uses').doc('c1_1').get()).exists, isTrue);
    });

    test('per-user limit: the second use is refused; another user can still use it', () async {
      await seedPromo(promo(limit: 10));
      await postWith(await RewardsService.reserve('SAVE10', 50000));
      await expectLater(RewardsService.reserve('SAVE10', 50000), throwsA(isA<PromoException>().having((e) => e.problem, 'problem', PromoProblem.usedUp)));
      uid = 'c2';
      expect((await RewardsService.reserve('SAVE10', 50000)).use, 1);
    });

    test('total limit: slots run out', () async {
      await seedPromo(promo(limit: 2));
      for (final u in ['a', 'b']) {
        uid = u;
        await postWith(await RewardsService.reserve('SAVE10', 50000));
      }
      uid = 'c';
      await expectLater(RewardsService.reserve('SAVE10', 50000), throwsA(isA<PromoException>().having((e) => e.problem, 'problem', PromoProblem.exhausted)));
    });

    test('credits spend writes a negative ledger line tied to the load', () async {
      await db.collection('users').doc('c1').collection('credits').doc('seed').set({'amountPaise': 20000, 'kind': 'admin_grant', 'createdAt': Timestamp.now()});
      await seedPromo(promo());
      final id = await postWith(await RewardsService.reserve('SAVE10', 50000), credits: 12000);
      final line = (await db.collection('users').doc('c1').collection('credits').doc('spend_$id').get()).data()!;
      expect(line['amountPaise'], -12000);
      expect(line['kind'], 'spend');
      expect(await RewardsService.balance(), 8000);
      expect(Load.fromDoc(await db.collection('loads').doc(id).get()).creditsUsedPaise, 12000);
    });
  });

  group('referrals', () {
    Future<void> signup(String id) => db.collection('users').doc(id).set({'role': 'customer', 'createdAt': Timestamp.now()});

    test('each user gets one stable code', () async {
      await signup('c1');
      final a = await RewardsService.ensureReferralCode(random: Random(1));
      expect(a, matches(RegExp(r'^[A-Z2-9]{6}$')));
      expect(await RewardsService.ensureReferralCode(random: Random(2)), a);
      expect((await db.collection('referral_codes').doc(a).get()).data()!['uid'], 'c1');
      uid = 'c2';
      await signup('c2');
      expect(await RewardsService.ensureReferralCode(random: Random(1)), isNot(a));
    });

    test('applying a friend\'s code credits both sides once', () async {
      await signup('c1');
      await signup('c2');
      final code = await RewardsService.ensureReferralCode();
      uid = 'c2';
      expect(await RewardsService.applyReferral(code), RewardsService.defaultReferralBonusPaise);
      expect(await RewardsService.balance(), 10000);
      uid = 'c1';
      expect(await RewardsService.balance(), 10000);
      uid = 'c2';
      await expectLater(RewardsService.applyReferral(code), throwsA(isA<ReferralException>().having((e) => e.problem, 'problem', ReferralProblem.alreadyReferred)));
      expect(await RewardsService.balance(), 10000);
    });

    test('abuse: own code, unknown code, old account', () async {
      await signup('c1');
      final code = await RewardsService.ensureReferralCode();
      await expectLater(RewardsService.applyReferral(code), throwsA(isA<ReferralException>().having((e) => e.problem, 'problem', ReferralProblem.ownCode)));
      uid = 'c2';
      await signup('c2');
      await expectLater(RewardsService.applyReferral('ZZZZZZ'), throwsA(isA<ReferralException>().having((e) => e.problem, 'problem', ReferralProblem.unknownCode)));
      await db.collection('users').doc('c2').update({'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 9)))});
      await expectLater(RewardsService.applyReferral(code), throwsA(isA<ReferralException>().having((e) => e.problem, 'problem', ReferralProblem.tooLate)));
      expect(await RewardsService.balance(), 0);
    });

    test('the admin-set bonus is used', () async {
      await signup('c1');
      await signup('c2');
      await RewardsService.setReferralBonus(25000);
      final code = await RewardsService.ensureReferralCode();
      uid = 'c2';
      expect(await RewardsService.applyReferral(code), 25000);
    });
  });

  test('admin grants and deductions are ledger lines', () async {
    await RewardsService.grantCredits('c1', 50000, note: 'goodwill');
    await RewardsService.grantCredits('c1', -20000);
    expect(await RewardsService.balance(), 30000);
    await expectLater(() => RewardsService.grantCredits('c1', 0), throwsArgumentError);
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: w)));
      await settle(tester);
    }

    testWidgets('offers section applies a code, shows the discount and the payable amount', (tester) async {
      await tester.runAsync(() => RewardsService.savePromo(promo(min: 20000)));
      OffersChoice? last;
      await pump(tester, Scaffold(body: SingleChildScrollView(child: OffersSection(total: 100000, onChanged: (c) => last = c))));
      await tester.enterText(find.byKey(const ValueKey('promoCode')), 'nope');
      await tester.tap(find.byKey(const ValueKey('promoApply')));
      await settle(tester);
      expect(find.text('This code does not exist'), findsOneWidget);
      expect(last?.promo, isNull);

      await tester.enterText(find.byKey(const ValueKey('promoCode')), 'save10');
      await tester.tap(find.byKey(const ValueKey('promoApply')));
      await settle(tester);
      expect(last?.promo?.code, 'SAVE10');
      expect(find.byKey(const ValueKey('promoApplied')), findsOneWidget);
      expect(find.textContaining('₹ 900'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('promoRemove')));
      await tester.pump();
      expect(last?.promo, isNull);
    });

    testWidgets('offers section: credits switch shows when there is a balance', (tester) async {
      await tester.runAsync(() => RewardsService.grantCredits('c1', 30000));
      OffersChoice? last;
      await pump(tester, Scaffold(body: SingleChildScrollView(child: OffersSection(total: 100000, onChanged: (c) => last = c))));
      expect(find.byKey(const ValueKey('useCredits')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('useCredits')));
      await tester.pump();
      expect(last?.useCredits, isTrue);
      expect(find.textContaining('₹ 700'), findsWidgets);
    });

    testWidgets('customer offers screen: code, balance, apply a friend\'s code', (tester) async {
      await tester.runAsync(() async {
        await db.collection('users').doc('c1').set({'role': 'customer', 'createdAt': Timestamp.now()});
        await db.collection('users').doc('c9').set({'role': 'customer', 'createdAt': Timestamp.now(), 'referralCode': 'FRIEND'});
        await db.collection('referral_codes').doc('FRIEND').set({'uid': 'c9'});
      });
      await pump(tester, const OffersScreen());
      expect(find.byKey(const ValueKey('myReferralCode')), findsOneWidget);
      expect(find.text('₹ 0'), findsWidgets);
      await tester.enterText(find.byKey(const ValueKey('referralInput')), 'friend');
      await tester.tap(find.byKey(const ValueKey('referralApply')));
      await settle(tester);
      expect(find.byKey(const ValueKey('referralInput')), findsNothing, reason: 'hidden once a referral is applied');
      expect(find.text('₹ 100'), findsWidgets);
    });

    testWidgets('admin creates a promo code and switches it off', (tester) async {
      await pump(tester, const AdminOffersScreen());
      await tester.tap(find.byKey(const ValueKey('newPromo')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('promoCodeField')), 'diwali20');
      await tester.enterText(find.byKey(const ValueKey('promoValue')), '20');
      await tester.enterText(find.byKey(const ValueKey('promoMax')), '150');
      await tester.enterText(find.byKey(const ValueKey('promoMin')), '500');
      await tester.enterText(find.byKey(const ValueKey('promoLimit')), '50');
      await tester.enterText(find.byKey(const ValueKey('promoPerUser')), '2');
      await tester.tap(find.byType(ElevatedButton).last);
      await settle(tester);
      final d = (await tester.runAsync(() => db.collection('promos').doc('DIWALI20').get()))!.data()!;
      expect(d['type'], 'percent');
      expect(d['value'], 20);
      expect(d['maxDiscountPaise'], 15000);
      expect(d['minOrderPaise'], 50000);
      expect(d['usageLimit'], 50);
      expect(d['perUserLimit'], 2);
      expect(d['active'], true);
      expect(find.byKey(const ValueKey('promo_DIWALI20')), findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(const ValueKey('promo_DIWALI20')), matching: find.byType(Switch)));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('promos').doc('DIWALI20').get()))!.data()!['active'], false);
    });
  });
}
