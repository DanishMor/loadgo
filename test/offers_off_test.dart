import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/offers/offers_switch.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/offers_switch_service.dart';
import 'package:transport_app/core/services/rewards_service.dart';
import 'package:transport_app/customer/offers_screen.dart';
import 'package:transport_app/customer/offers_section.dart';

import 'test_utils.dart';

/// MASTER-5 Task 41: promo codes, credits and referral behave when their
/// admin switch is OFF (the default), and when only some are ON.
void main() {
  late FakeFirebaseFirestore db;
  final promo = Promo(code: 'SAVE10', type: Promo.percent, value: 10, maxDiscountPaise: 0, minOrderPaise: 0, expiresAt: DateTime(2030), usageLimit: 10, perUserLimit: 1, active: true);

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
    OffersSwitchService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(OffersSwitchService.reset);

  test('the default is everything OFF', () {
    expect(OffersSwitchService.current, OffersSwitch.allOff);
    expect(OffersSwitchService.current.any, isFalse);
    expect(OffersSwitch.fromMap(null), OffersSwitch.allOff);
    expect(OffersSwitch.fromMap({'promoEnabled': 'yes'}), OffersSwitch.allOff, reason: 'only a real true turns a switch on');
  });

  test('a code or credits picked earlier are dropped when their switch is OFF', () {
    final picked = OffersChoice(promo: promo, useCredits: true);
    final off = allowedOffers(picked, OffersSwitch.allOff);
    expect(off.promo, isNull);
    expect(off.useCredits, isFalse);
    final onlyPromo = allowedOffers(picked, const OffersSwitch(promo: true));
    expect(onlyPromo.promo, promo);
    expect(onlyPromo.useCredits, isFalse);
    final onlyCredits = allowedOffers(picked, const OffersSwitch(credits: true));
    expect(onlyCredits.promo, isNull);
    expect(onlyCredits.useCredits, isTrue);
  });

  test('with the offers OFF the customer pays the full quote', () {
    final off = allowedOffers(OffersChoice(promo: promo, useCredits: true), OffersSwitch.allOff);
    expect(payableAfterOffers(total: 100000, promo: off.promo, creditsBalance: 50000, useCredits: off.useCredits), 100000);
    expect(creditsToSpend(total: 100000, promo: off.promo, creditsBalance: 50000, useCredits: off.useCredits), 0);
  });

  testWidgets('the Post Load offers block is empty while everything is OFF, then shows only what is ON', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: OffersSection(total: 100000, onChanged: (_) {})))));
    await settle(tester);
    expect(find.byKey(const ValueKey('promoCode')), findsNothing);
    expect(find.byKey(const ValueKey('useCredits')), findsNothing);
    OffersSwitchService.notifier.value = const OffersSwitch(promo: true);
    await settle(tester);
    expect(find.byKey(const ValueKey('promoCode')), findsOneWidget);
    expect(find.byKey(const ValueKey('useCredits')), findsNothing);
  });

  testWidgets('the Offers screen with referral OFF makes no referral code and shows no referral card', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: OffersScreen())));
    await settle(tester);
    expect((await db.collection('referral_codes').get()).docs, isEmpty);
    expect(find.byKey(const ValueKey('myReferralCode')), findsNothing);
  });

  test('the referral bonus falls back to the default and an admin change is seen at once (it is never cached: the rules compare it)', () async {
    expect(await RewardsService.referralBonus(), RewardsService.defaultReferralBonusPaise);
    await RewardsService.setReferralBonus(25000);
    expect(await RewardsService.referralBonus(), 25000);
  });
}
