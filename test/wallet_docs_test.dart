import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/services/payment_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';

/// F13 and F14: the wallet docs name what the code has, and commission is plain integer maths.
void main() {
  String doc(String n) => File('docs/$n').readAsStringSync();

  test('the three wallet docs exist and name every wallet flag and the threats', () {
    final security = doc('WALLET_SECURITY.md');
    for (final k in [FeatureKey.walletMakerChecker, FeatureKey.walletStepUp, FeatureKey.walletLimits, FeatureKey.appLock, FeatureKey.secureScreens]) {
      expect(security, contains(k), reason: k);
    }
    for (final t in ['Double spend', 'Replay', 'Race', 'Tampering', 'Insider fraud']) {
      expect(security.toLowerCase(), contains(t.toLowerCase()), reason: t);
    }
    final live = doc('WALLET_GO_LIVE.md');
    expect(live, contains('Rollback'));
    for (final k in [FeatureKey.walletHub, FeatureKey.walletMakerChecker, FeatureKey.walletStepUp, FeatureKey.walletLimits]) {
      expect(live, contains(k), reason: k);
    }
    final legal = doc('WALLET_LEGAL.md');
    for (final w in ['RBI', 'TDS', 'GST', 'KYC', 'refund']) {
      expect(legal.toLowerCase(), contains(w.toLowerCase()), reason: w);
    }
  });

  test('commission is whole paise by integer basis points, never more than the amount', () {
    PricingService.reset();
    final c = PricingService.config;
    expect(PaymentService.commissionFor(1000000), -(1000000 * (c.commissionPercent * 100).round() / 10000).round());
    for (final a in [1, 2, 3, 99, 100, 101, 12345, 1000000, 99999999]) {
      final x = PaymentService.commissionFor(a);
      expect(x, lessThanOrEqualTo(0));
      expect(-x, lessThanOrEqualTo((a / 2).ceil()), reason: 'the rules allow at most half: amount $a');
    }
    expect(PaymentService.commissionFor(0), 0);
  });
}
