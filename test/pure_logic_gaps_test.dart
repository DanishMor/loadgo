import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/bilty/lr_visibility.dart';
import 'package:transport_app/core/comm/chat_strikes.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/services/pricing_service.dart';

/// P9: the least-covered pure logic (fare, cancellation, strike ladder, LR copy
/// privacy, booking flow, ledger). No widgets: plain unit tests.
void main() {
  const rule = PricingRule(
    baseFare: 10000,
    perKm: 2000,
    minimumFare: 50000,
    loadingCharge: 3000,
    unloadingCharge: 2000,
    waitingPerHour: 5000,
    perExtraStop: 1500,
    helperCharge: 30000,
    rentalPerHour: 40000,
    rentalKmPerHour: 10,
    extraKmCharge: 1500,
    moversPerItem: 500,
    moversPerFloor: 700,
    packingPerItem: 300,
  );

  group('FareCalculator.calculate', () {
    test('every line adds up: waiting by started hour, stops, helper, movers, packing', () {
      final b = FareCalculator.calculate(
        rule: rule,
        distanceKm: 20,
        waitingMinutes: 61,
        extraStops: 2,
        helpers: 1,
        movers: const MoversDetails(items: {'sofa': 2, 'box': 10}, floor: 3, hasLift: false, packingNeeded: true),
      );
      expect(b.waitingCharge, 10000); // 61 min = 2 started hours
      expect(b.extraStopCharge, 3000);
      expect(b.helperCharge, 30000);
      expect(b.itemHandlingCharge, 6000); // 12 units
      expect(b.floorCharge, 2100); // 3 floors, no lift
      expect(b.packingCharge, 3600);
      expect(b.minimumFareAdjustment, 0);
      expect(b.tripFare, 109700);
      expect(b.total, b.tripFare + b.platformFee + b.gst);
    });

    test('a lift removes the floor charge; a negative floor or stop count costs nothing', () {
      final lift = FareCalculator.calculate(rule: rule, distanceKm: 5, movers: const MoversDetails(items: {'a': 1}, floor: 4, hasLift: true));
      expect(lift.floorCharge, 0);
      final neg = FareCalculator.calculate(rule: rule, distanceKm: 5, extraStops: -3, movers: const MoversDetails(items: {'a': 1}, floor: -2, hasLift: false));
      expect(neg.floorCharge, 0);
      expect(neg.extraStopCharge, 0);
      final noPack = FareCalculator.calculate(rule: rule, distanceKm: 5, movers: const MoversDetails(items: {'a': 3}));
      expect(noPack.packingCharge, 0);
    });

    test('the minimum fare tops a short trip up', () {
      final b = FareCalculator.calculate(rule: rule, distanceKm: 0, loading: false, unloading: false);
      expect(b.baseFare, 10000);
      expect(b.minimumFareAdjustment, 40000);
      expect(b.tripFare, 50000);
    });

    test('platform fee and GST are percentages of the right base', () {
      final b = FareCalculator.calculate(rule: rule, distanceKm: 100, platformFeePercent: 10, gstPercent: 18);
      expect(b.platformFee, (b.tripFare * 0.10).round());
      expect(b.gst, ((b.tripFare + b.platformFee) * 0.18).round());
    });

    test('bad input throws', () {
      expect(() => FareCalculator.calculate(rule: rule, distanceKm: -1), throwsArgumentError);
      expect(() => FareCalculator.calculate(rule: rule, distanceKm: 1, helpers: maxHelpers + 1), throwsArgumentError);
      expect(() => FareCalculator.calculate(rule: rule, distanceKm: 1, helpers: -1), throwsArgumentError);
    });

    test('detention: the first hour is free, then every started hour', () {
      expect(FareCalculator.detentionCharge(rule, 60), 0);
      expect(FareCalculator.detentionCharge(rule, 61), 5000);
      expect(FareCalculator.detentionCharge(rule, 120), 5000);
      expect(FareCalculator.detentionCharge(rule, 121), 10000);
      expect(FareCalculator.detentionCharge(rule, 90, freeMinutes: 30), 5000);
    });
  });

  group('FareCalculator.calculateRental', () {
    test('a quote has no extras and shows the included km', () {
      final b = FareCalculator.calculateRental(rule: rule, hours: 4);
      expect(b.rentalCharge, 160000);
      expect(b.extraKmCharge, 0);
      expect(b.extraHourCharge, 0);
      expect(b.distanceKm, 40);
      expect(b.tripFare, 160000);
    });

    test('after the trip: extra km, extra started hours (hourly price when no extra rate), helpers, fee and GST', () {
      final b = FareCalculator.calculateRental(rule: rule, hours: 4, usedKm: 55, usedMinutes: 301, helpers: 2, platformFeePercent: 10, gstPercent: 18);
      expect(b.extraKmCharge, 15 * 1500);
      expect(b.extraHourCharge, 2 * 40000); // 61 minutes over = 2 started hours at the hourly price
      expect(b.helperCharge, 60000);
      expect(b.tripFare, 160000 + 22500 + 80000 + 60000);
      expect(b.platformFee, 32250);
      expect(b.gst, 63855);
      expect(b.distanceKm, 55);
      expect(b.total, b.tripFare + b.platformFee + b.gst);
    });

    test('inside the package nothing extra is billed; an own extra-hour rate wins', () {
      final inside = FareCalculator.calculateRental(rule: rule, hours: 8, usedKm: 80, usedMinutes: 480);
      expect(inside.extraKmCharge, 0);
      expect(inside.extraHourCharge, 0);
      final own = PricingRule(baseFare: 0, perKm: 0, minimumFare: 0, rentalPerHour: 40000, extraHourCharge: 25000);
      expect(own.effectiveExtraHour, 25000);
      expect(FareCalculator.calculateRental(rule: own, hours: 4, usedMinutes: 241).extraHourCharge, 25000);
      expect(rule.effectiveExtraHour, 40000);
    });

    test('only 4, 8 and 12 hours; helpers are limited', () {
      expect(() => FareCalculator.calculateRental(rule: rule, hours: 5), throwsArgumentError);
      expect(() => FareCalculator.calculateRental(rule: rule, hours: 4, helpers: maxHelpers + 1), throwsArgumentError);
      for (final h in rentalHourOptions) {
        expect(FareCalculator.calculateRental(rule: rule, hours: h).rentalCharge, 40000 * h);
      }
    });
  });

  group('rule and movers data', () {
    test('PricingRule toMap and fromMap round trip; a missing key falls back', () {
      final back = PricingRule.fromMap(rule.toMap(), const PricingRule(baseFare: 1, perKm: 1, minimumFare: 1));
      expect(back.toMap(), rule.toMap());
      final partial = PricingRule.fromMap({'perKm': 9}, rule);
      expect(partial.perKm, 9);
      expect(partial.baseFare, rule.baseFare);
    });

    test('MoversDetails: units, map round trip, defaults from nothing', () {
      const m = MoversDetails(items: {'sofa': 2, 'box': 10}, floor: 2, hasLift: false, packingNeeded: true);
      expect(m.units, 12);
      final back = MoversDetails.fromMap(m.toMap());
      expect(back.items, m.items);
      expect(back.floor, 2);
      expect(back.hasLift, isFalse);
      expect(back.packingNeeded, isTrue);
      final empty = MoversDetails.fromMap(null);
      expect(empty.items, isEmpty);
      expect(empty.hasLift, isTrue);
      expect(empty.floor, 0);
    });

    test('parseItems: names, quantities, merged duplicates, blank lines; bad quantity gives null', () {
      expect(MoversDetails.parseItems('sofa x2\nbox 10\n\n  chair '), {'sofa': 2, 'box': 10, 'chair': 1});
      expect(MoversDetails.parseItems('sofa x2\nsofa 3'), {'sofa': 5});
      expect(MoversDetails.parseItems(''), isEmpty);
      expect(MoversDetails.parseItems('table 0'), isNull);
      expect(MoversDetails.parseItems('table 100'), isNull);
      // A name that ends in x or X keeps its last letter (the quantity needs a space or a star).
      expect(MoversDetails.parseItems('Max 4\nbox x3\nsofa*2'), {'Max': 4, 'box': 3, 'sofa': 2});
    });
  });

  group('CancellationPolicy', () {
    const p = CancellationPolicy();
    test('free inside the free minutes, then a percent of the fare within min and max', () {
      expect(p.chargeFor(elapsed: const Duration(minutes: 14), farePaise: 100000), 0);
      expect(p.chargeFor(elapsed: const Duration(minutes: 15), farePaise: 100000), 10000);
      expect(p.chargeFor(elapsed: const Duration(minutes: 30), farePaise: 10), 5000); // minimum
      expect(p.chargeFor(elapsed: const Duration(minutes: 30), farePaise: 100000000), 100000); // maximum
      expect(p.chargeFor(elapsed: const Duration(minutes: 30)), 5000); // no estimate
    });

    test('scheduled: free until the free hours before pickup, charged after', () {
      final at = DateTime(2026, 10, 12, 10);
      expect(p.chargeForScheduled(now: at.subtract(const Duration(hours: 3)), scheduledAt: at, farePaise: 100000), 0);
      expect(p.chargeForScheduled(now: at.subtract(const Duration(hours: 2)), scheduledAt: at, farePaise: 100000), 0); // exactly on the line
      expect(p.chargeForScheduled(now: at.subtract(const Duration(hours: 1)), scheduledAt: at, farePaise: 100000), 10000);
    });

    test('a max below the min cannot break the clamp; fromMap and toMap', () {
      const odd = CancellationPolicy(minCharge: 8000, maxCharge: 100);
      expect(odd.chargeFor(elapsed: const Duration(hours: 1), farePaise: 1000000), 8000);
      expect(CancellationPolicy.fromMap(null).toMap(), const CancellationPolicy().toMap());
      final c = CancellationPolicy.fromMap({'freeMinutes': 5, 'chargePercent': 20, 'minCharge': 1000, 'maxCharge': 2000, 'scheduledFreeHours': 6});
      expect(c.freeMinutes, 5);
      expect(c.chargePercent, 20);
      expect(c.scheduledFreeHours, 6);
      expect(CancellationPolicy.fromMap(c.toMap()).toMap(), c.toMap());
    });
  });

  group('PricingService', () {
    tearDown(PricingService.reset);

    test('quote and quoteRental use the configured rule, fee and GST', () {
      final c = PricingService.config;
      final r = c.ruleFor('unknown_type', 'lcv');
      final want = FareCalculator.calculate(rule: r, distanceKm: 120, platformFeePercent: c.platformFeePercent, gstPercent: c.gstPercent, extraStops: 1, helpers: 1);
      final got = PricingService.quote(vehicleType: 'unknown_type', distanceKm: 120, extraStops: 1, helpers: 1);
      expect(got.total, want.total);
      final rent = PricingService.quoteRental(vehicleType: 'unknown_type', hours: 8, usedKm: 200);
      expect(rent.rentalCharge, r.rentalPerHour * 8);
      expect(PricingService.rentalIncludedKm('unknown_type', 8), 8 * r.rentalKmPerHour);
    });

    test('route kilometres: known cities, unknown place, too few places', () {
      final km = PricingService.estimateKm('Delhi', 'Mumbai');
      expect(km, isNotNull);
      expect(km!, greaterThan(1000));
      expect(PricingService.estimateKm('Delhi', 'Nowhereville'), isNull);
      expect(PricingService.estimateRouteKm(['Delhi']), isNull);
      expect(PricingService.estimateRouteKm(['Delhi', 'Nowhereville', 'Mumbai']), isNull);
      final via = PricingService.estimateRouteKm(['Delhi', 'Mumbai', 'Delhi']);
      expect(via, km * 2);
    });
  });

  group('ChatLadder and appeals', () {
    test('the block grows with the strikes; only 5 and more need a review', () {
      expect(ChatLadder.blockFor(0), isNull);
      expect(ChatLadder.blockFor(ChatLadder.warnings), isNull);
      expect(ChatLadder.blockFor(3), const Duration(hours: 24));
      expect(ChatLadder.blockFor(4), const Duration(days: 3));
      expect(ChatLadder.blockFor(5), const Duration(days: 7));
      expect(ChatLadder.blockFor(9), const Duration(days: 7));
      expect(ChatLadder.needsReview(4), isFalse);
      expect(ChatLadder.needsReview(5), isTrue);
    });

    test('one strike comes off after the clean days, never before, never with none', () {
      final last = DateTime(2026, 1, 1);
      final due = last.add(const Duration(days: ChatLadder.decayDays));
      expect(ChatLadder.canDecay(strikes: 2, lastChange: last, now: due.subtract(const Duration(seconds: 1))), isFalse);
      expect(ChatLadder.canDecay(strikes: 2, lastChange: last, now: due), isTrue);
      expect(ChatLadder.canDecay(strikes: 0, lastChange: last, now: due), isFalse);
      expect(ChatLadder.canDecay(strikes: 2, lastChange: null, now: due), isFalse);
    });

    test('ChatStatus reads a user document and knows when it is blocked', () {
      DateTime toDate(Object? v) => v as DateTime;
      final none = ChatStatus.fromUser(null, toDate);
      expect(none.strikes, 0);
      expect(none.review, isFalse);
      expect(none.isBlocked(DateTime(2026)), isFalse);
      final until = DateTime(2026, 5, 1);
      final s = ChatStatus.fromUser({'chatStrikes': 3, 'chatSeq': 7, 'chatBlockedUntil': until, 'chatStrikeAt': DateTime(2026, 4, 30), 'chatReview': true}, toDate);
      expect(s.strikes, 3);
      expect(s.seq, 7);
      expect(s.review, isTrue);
      expect(s.isBlocked(until.subtract(const Duration(minutes: 1))), isTrue);
      expect(s.isBlocked(until), isFalse);
    });

    test('a granted appeal takes one strike off and lifts what the lower count no longer calls for', () {
      final g5 = AppealOutcome.grant(5);
      expect(g5.strikes, 4);
      expect(g5.liftBlock, isFalse); // 4 strikes still mean 3 days
      expect(g5.clearReview, isTrue);
      expect(AppealOutcome.grant(4).liftBlock, isFalse);
      expect(AppealOutcome.grant(3).liftBlock, isTrue);
      expect(AppealOutcome.grant(1).strikes, 0);
      expect(AppealOutcome.grant(0).strikes, 0);
      final at = DateTime(2026, 3, 1);
      expect(AppealOutcome.open(at, at.add(const Duration(days: AppealOutcome.windowDays - 1))), isTrue);
      expect(AppealOutcome.open(at, at.add(const Duration(days: AppealOutcome.windowDays))), isFalse);
    });
  });

  group('LR copy privacy', () {
    final sensitiveForDriver = {...LrFields.rateKeys, LrFields.marginKey, ...LrFields.phoneKeys};
    test('the driver copy never has rate, margin or phones, in any mode', () {
      for (final mode in ComplianceMode.all) {
        for (final grant in [false, true]) {
          for (final rate in [false, true]) {
            final f = LrVisibility.fields(LrCopy.driver, consigneeShowsRate: rate, complianceMode: mode, grantValid: grant);
            expect(f.intersection(sensitiveForDriver), isEmpty, reason: '$mode grant=$grant rate=$rate');
          }
        }
      }
    });

    test('the consignee copy never has margin or phones; the rate only when switched on', () {
      for (final mode in ComplianceMode.all) {
        final off = LrVisibility.fields(LrCopy.consignee, complianceMode: mode);
        final on = LrVisibility.fields(LrCopy.consignee, consigneeShowsRate: true, complianceMode: mode);
        for (final f in [off, on]) {
          expect(f.contains(LrFields.marginKey), isFalse);
          expect(f.intersection(LrFields.phoneKeys.toSet()), isEmpty);
        }
        expect(off.intersection(LrFields.rateKeys.toSet()), isEmpty);
        expect(on.containsAll(LrFields.rateKeys), isTrue);
      }
    });

    test('compliance: full copy always; driver copy on show or a valid grant; consignee on show', () {
      expect(LrVisibility.showsCompliance(LrCopy.full), isTrue);
      expect(LrVisibility.showsCompliance(LrCopy.driver), isFalse);
      expect(LrVisibility.showsCompliance(LrCopy.driver, grantValid: true), isTrue);
      expect(LrVisibility.showsCompliance(LrCopy.driver, complianceMode: ComplianceMode.show), isTrue);
      expect(LrVisibility.showsCompliance(LrCopy.consignee, complianceMode: ComplianceMode.show), isTrue);
      expect(LrVisibility.showsCompliance(LrCopy.consignee, complianceMode: ComplianceMode.inspectionOnRequest), isFalse);
      expect(LrVisibility.driverMaySeeRate(), isFalse);
      expect(ComplianceMode.normalise('nonsense'), ComplianceMode.hide);
    });

    test('every copy carries the public keys', () {
      for (final copy in LrCopy.all) {
        expect(LrVisibility.fields(copy).containsAll(LrFields.publicKeys), isTrue, reason: copy);
      }
    });
  });

  group('booking flow', () {
    test('next follows the flow in order and ends at delivered', () {
      for (var i = 0; i < BookingStatus.flow.length - 1; i++) {
        expect(BookingStatus.next(BookingStatus.flow[i]), BookingStatus.flow[i + 1]);
      }
      expect(BookingStatus.next(BookingStatus.delivered), isNull);
      expect(BookingStatus.next(BookingStatus.cancelled), isNull);
      expect(BookingStatus.next('nonsense'), isNull);
      expect(BookingStatus.flow.contains(BookingStatus.cancelled), isFalse);
    });

    test('OTP only for pickup and delivery; the driver may back out only early', () {
      for (final s in BookingStatus.flow) {
        expect(BookingStatus.needsOtp(s), s == BookingStatus.pickedUp || s == BookingStatus.delivered, reason: s);
      }
      expect(BookingStatus.driverCancellable, [BookingStatus.accepted, BookingStatus.driverArriving]);
      for (final s in BookingStatus.driverCancellable) {
        expect(BookingStatus.flow.indexOf(s), lessThan(BookingStatus.flow.indexOf(BookingStatus.loading)));
      }
    });
  });

  group('ledger', () {
    test('LedgerEntry.fromDoc reads a line and survives missing fields', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('ledger').doc('b1_trip_earning').set({
        'driverId': 'd1',
        'bookingId': 'b1',
        'type': LedgerType.tripEarning,
        'amountPaise': 90000,
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 3)),
      });
      await db.collection('ledger').doc('odd').set({'amountPaise': 12.4});
      final e = LedgerEntry.fromDoc(await db.collection('ledger').doc('b1_trip_earning').get());
      expect(e.id, 'b1_trip_earning');
      expect(e.driverId, 'd1');
      expect(e.amountPaise, 90000);
      expect(e.createdAt, DateTime(2026, 2, 3));
      final odd = LedgerEntry.fromDoc(await db.collection('ledger').doc('odd').get());
      expect(odd.driverId, '');
      expect(odd.type, '');
      expect(odd.amountPaise, 12);
      expect(odd.createdAt, isNull);
    });

    test('WalletSummary: earnings plus (negative) commission is the net; unknown types are ignored', () {
      LedgerEntry line(String type, int paise) => LedgerEntry(id: '$type$paise', driverId: 'd', bookingId: 'b', type: type, amountPaise: paise);
      final s = WalletSummary.of([
        line(LedgerType.tripEarning, 100000),
        line(LedgerType.platformCommission, -10000),
        line(LedgerType.tripEarning, 50000),
        line(LedgerType.platformCommission, -5000),
        line('something_else', 999999),
      ]);
      expect(s.earnings, 150000);
      expect(s.commission, -15000);
      expect(s.net, 135000);
      expect(WalletSummary.of(const []).net, 0);
      expect(PaymentMode.all, [PaymentMode.cash, PaymentMode.upiDirect]);
    });
  });
}
