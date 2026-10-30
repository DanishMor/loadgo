import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/trust/public_trust.dart';
import 'package:transport_app/core/trust/public_trust_card.dart';
import 'package:transport_app/core/trust/reliability.dart';
import 'package:transport_app/core/trust/trust_badges.dart';

/// E34: reliability tier (the same cases as functions/test/unit/trust.test.js) and the offer badge.
void main() {
  setUp(() {
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  ReliabilityTier? tier({int delivered = 0, int driverCancelled = 0, int onTimeKnown = 0, int onTimeOk = 0, double? rating, int ratingCount = 0}) =>
      Reliability.tierOf(Reliability.score(delivered: delivered, driverCancelled: driverCancelled, onTimeKnown: onTimeKnown, onTimeOk: onTimeOk, rating: rating, ratingCount: ratingCount));

  test('the same tiers as the server formula', () {
    expect(tier(delivered: 9, rating: 5, ratingCount: 50), isNull);
    expect(tier(delivered: 40, onTimeKnown: 30, onTimeOk: 29, rating: 4.8, ratingCount: 20), ReliabilityTier.top);
    expect(tier(delivered: 18, driverCancelled: 2, onTimeKnown: 10, onTimeOk: 8, rating: 4.5, ratingCount: 10), ReliabilityTier.good);
    expect(tier(delivered: 14, driverCancelled: 6, onTimeKnown: 10, onTimeOk: 5, rating: 3.5, ratingCount: 10), isNull);
    expect(tier(delivered: 12, onTimeKnown: 2, ratingCount: 1, rating: 1), ReliabilityTier.top);
    expect(tier(delivered: 20, onTimeKnown: 10, onTimeOk: 99, rating: 9, ratingCount: 10), ReliabilityTier.top);
  });

  test('from the app badges; parse only top and good', () {
    const b = TrustBadges(finished: 20, delivered: 19, onTimePercent: 90, onTimeKnown: 10);
    expect(Reliability.fromBadges(b, rating: 4.7, ratingCount: 8), ReliabilityTier.top);
    expect(Reliability.parse('good'), ReliabilityTier.good);
    expect(Reliability.parse('excellent'), isNull);
    expect(PublicTrust.fromMap('d1', {'reliability': 'top'}).reliability, ReliabilityTier.top);
    expect(PublicTrust.fromMap('d1', {'reliability': 7}).reliability, isNull);
  });

  Widget host(Widget child) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: child)));

  testWidgets('offer card: the tier word only with reliabilityBadges on; never a number', (t) async {
    const trust = PublicTrust(uid: 'd1', trips: 40, rating: 4.8, ratingCount: 20, verified: true, reliability: ReliabilityTier.top);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.tripTrustCard: true});
    await t.pumpWidget(host(PublicTrustCard(driverId: 'd1', source: Stream.value(trust))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ptRel_top')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.tripTrustCard: true, FeatureKey.reliabilityBadges: true});
    await t.pumpWidget(host(PublicTrustCard(key: const ValueKey(2), driverId: 'd1', source: Stream.value(trust))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ptRel_top')), findsOneWidget);
    expect(find.text('Highly reliable'), findsOneWidget);
  });
}
