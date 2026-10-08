import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/bilty/lr_visibility.dart';
import 'package:transport_app/core/comm/chat_strikes.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';

/// MASTER-5 Task 43: the pure rules, checked over many inputs instead of a few.
void main() {
  group('fare', () {
    const rule = PricingRule(baseFare: 50000, perKm: 2200, minimumFare: 150000, loadingCharge: 30000, unloadingCharge: 30000, waitingPerHour: 20000, perExtraStop: 15000, helperCharge: 40000);

    FareBreakdown f(int km, {num fee = 5, num gst = 18, int waiting = 0, int stops = 0, int helpers = 0}) =>
        FareCalculator.calculate(rule: rule, distanceKm: km, platformFeePercent: fee, gstPercent: gst, waitingMinutes: waiting, extraStops: stops, helpers: helpers);

    test('the total is exactly the parts added up, for 0 to 3000 km', () {
      for (var km = 0; km <= 3000; km += 7) {
        final b = f(km, waiting: km % 200, stops: km % 4, helpers: km % 3);
        expect(b.total, b.tripFare + b.platformFee + b.gst, reason: '$km km');
        expect(b.tripFare, greaterThanOrEqualTo(rule.minimumFare), reason: '$km km reaches the minimum fare');
        for (final part in [b.tripFare, b.platformFee, b.gst, b.total]) {
          expect(part, greaterThanOrEqualTo(0));
        }
      }
    });

    test('more distance never costs less; more waiting, stops or helpers never cost less', () {
      var last = 0;
      for (var km = 0; km <= 2000; km += 5) {
        final t = f(km).total;
        expect(t, greaterThanOrEqualTo(last), reason: '$km km');
        last = t;
      }
      expect(f(300, waiting: 180).total, greaterThanOrEqualTo(f(300, waiting: 60).total));
      expect(f(300, stops: 3).total, greaterThan(f(300, stops: 0).total));
      expect(f(300, helpers: 2).total, greaterThan(f(300).total));
    });

    test('GST is charged on the trip fare plus the platform fee; a zero rate gives zero', () {
      final b = f(400, fee: 10, gst: 18);
      expect(b.platformFee, (b.tripFare * 10 / 100).round());
      expect(b.gst, ((b.tripFare + b.platformFee) * 18 / 100).round());
      final none = f(400, fee: 0, gst: 0);
      expect(none.platformFee, 0);
      expect(none.gst, 0);
      expect(none.total, none.tripFare);
    });

    test('free waiting minutes cost nothing, then every started hour is charged', () {
      expect(FareCalculator.detentionCharge(rule, 0), 0);
      expect(FareCalculator.detentionCharge(rule, 60), 0);
      expect(FareCalculator.detentionCharge(rule, 61), 20000);
      expect(FareCalculator.detentionCharge(rule, 120), 20000);
      expect(FareCalculator.detentionCharge(rule, 121), 40000);
    });

    test('bad inputs are refused', () {
      expect(() => f(-1), throwsArgumentError);
      expect(() => f(10, helpers: -1), throwsArgumentError);
      expect(() => f(10, helpers: maxHelpers + 1), throwsArgumentError);
    });
  });

  group('promo', () {
    Promo p(String type, int value, {int max = 0}) =>
        Promo(code: 'X', type: type, value: value, maxDiscountPaise: max, minOrderPaise: 0, expiresAt: DateTime(2030), usageLimit: 10, perUserLimit: 1, active: true);

    test('a discount is never negative and never more than the order, over many orders', () {
      for (final promo in [p(Promo.percent, 10), p(Promo.percent, 100), p(Promo.percent, 33, max: 5000), p(Promo.flat, 20000), p(Promo.flat, 1, max: 1)]) {
        for (var total = 0; total <= 400000; total += 997) {
          final d = promo.discountFor(total);
          expect(d, inInclusiveRange(0, total), reason: '${promo.type} ${promo.value} on $total');
        }
      }
    });

    test('a bigger order never gets a smaller percent discount', () {
      final promo = p(Promo.percent, 15, max: 30000);
      var last = 0;
      for (var total = 0; total <= 300000; total += 313) {
        final d = promo.discountFor(total);
        expect(d, greaterThanOrEqualTo(last));
        last = d;
      }
    });
  });

  group('chat strike ladder', () {
    test('the block only gets longer as strikes grow, review from five', () {
      Duration none = Duration.zero;
      var last = none;
      for (var s = 0; s <= 12; s++) {
        final b = ChatLadder.blockFor(s) ?? none;
        expect(b, greaterThanOrEqualTo(last), reason: '$s strikes');
        last = b;
        expect(ChatLadder.needsReview(s), s >= 5);
      }
      expect(ChatLadder.blockFor(2), isNull);
      expect(ChatLadder.blockFor(3), const Duration(hours: 24));
      expect(ChatLadder.blockFor(4), const Duration(days: 3));
      expect(ChatLadder.blockFor(5), const Duration(days: 7));
      expect(ChatLadder.blockFor(40), const Duration(days: 7));
    });

    test('a strike comes off on the 30th clean day, not before, and only if there is one', () {
      final last = DateTime(2026, 9, 1);
      expect(ChatLadder.canDecay(strikes: 2, lastChange: last, now: DateTime(2026, 9, 30, 23, 59)), isFalse);
      expect(ChatLadder.canDecay(strikes: 2, lastChange: last, now: DateTime(2026, 10, 1)), isTrue);
      expect(ChatLadder.canDecay(strikes: 0, lastChange: last, now: DateTime(2027)), isFalse);
      expect(ChatLadder.canDecay(strikes: 2, lastChange: null, now: DateTime(2027)), isFalse);
    });
  });

  group('bilty visibility matrix', () {
    final modes = [ComplianceMode.hide, ComplianceMode.show, ComplianceMode.inspectionOnRequest];
    final copies = [LrCopy.full, LrCopy.consignee, LrCopy.driver];

    test('across every copy, mode, grant and rate switch: the driver never gets rate, margin or phones', () {
      for (final mode in modes) {
        for (final grant in [false, true]) {
          for (final showRate in [false, true]) {
            final d = LrVisibility.fields(LrCopy.driver, complianceMode: mode, grantValid: grant, consigneeShowsRate: showRate);
            expect(d.intersection({...LrFields.rateKeys, LrFields.marginKey, ...LrFields.phoneKeys}), isEmpty, reason: '$mode grant=$grant rate=$showRate');
          }
        }
      }
    });

    test('the consignee never gets margin or phones; the full copy has everything', () {
      for (final mode in modes) {
        for (final showRate in [false, true]) {
          final c = LrVisibility.fields(LrCopy.consignee, complianceMode: mode, consigneeShowsRate: showRate);
          expect(c.intersection({LrFields.marginKey, ...LrFields.phoneKeys}), isEmpty);
          expect(c.containsAll(LrFields.publicKeys), isTrue);
        }
      }
      final full = LrVisibility.fields(LrCopy.full);
      for (final copy in copies) {
        for (final mode in modes) {
          expect(full.containsAll(LrVisibility.fields(copy, complianceMode: mode, grantValid: true, consigneeShowsRate: true)), isTrue, reason: '$copy $mode is inside the full copy');
        }
      }
    });

    test('compliance reaches the driver only in show mode or with a valid grant', () {
      for (final mode in modes) {
        for (final grant in [false, true]) {
          final shows = LrVisibility.showsCompliance(LrCopy.driver, complianceMode: mode, grantValid: grant);
          expect(shows, mode == ComplianceMode.show || grant, reason: '$mode grant=$grant');
        }
      }
      expect(LrVisibility.driverMaySeeRate(), isFalse);
    });
  });
}
