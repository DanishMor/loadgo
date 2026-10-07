import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_rating_burst_screen.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/analytics/rating_burst.dart';
import 'package:transport_app/core/l10n/abuse_strings.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/rating.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/pricing/offer_bounds.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/chat_service.dart';
import 'package:transport_app/core/services/offer_service.dart';

import 'test_utils.dart';

Rating r(String id, String rater, String rated, int stars, DateTime at) =>
    Rating(id: id, bookingId: 'b$id', raterId: rater, ratedId: rated, stars: stars, comment: '', createdAt: Timestamp.fromDate(at));

void main() {
  late FakeFirebaseFirestore db;
  final now = DateTime(2026, 10, 7, 12);

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'driver1');
  });

  group('OfferBounds', () {
    test('30% to 300%, inclusive, integer paise', () {
      expect(OfferBounds.minPaise(1000000), 300000);
      expect(OfferBounds.maxPaise(1000000), 3000000);
      expect(OfferBounds.check(299999, 1000000), 'low');
      expect(OfferBounds.check(300000, 1000000), isNull);
      expect(OfferBounds.check(3000000, 1000000), isNull);
      expect(OfferBounds.check(3000001, 1000000), 'high');
    });

    test('rounds the minimum up (333 paise at 30% is 100)', () {
      expect(OfferBounds.minPaise(333), 100);
      expect(OfferBounds.check(99, 333), 'low');
      expect(OfferBounds.check(100, 333), isNull);
      expect(OfferBounds.minPaise(1), 1);
    });

    test('no estimate or a zero one means no limits', () {
      expect(OfferBounds.check(1, null), isNull);
      expect(OfferBounds.check(99999999, 0), isNull);
      expect(OfferBounds.check(99999999, -5), isNull);
    });
  });

  group('OfferService.send bounds', () {
    Future<(Load, Vehicle)> seed(int? estimate) async {
      await db.collection('loads').doc('L1').set({
        'shipperId': 'c1', 'pickup': 'Delhi', 'drop': 'Jaipur', 'status': 'open', 'cargoType': 'Steel', 'vehicleType': 'lcv', 'weight': 2,
        if (estimate != null) 'estimate': {'baseFare': estimate},
      });
      await db.collection('vehicles').doc('v1').set({'ownerId': 'driver1', 'number': 'MH12AB1234', 'type': 'lcv', 'capacity': 3, 'status': 'active'});
      await db.collection('users').doc('driver1').set({'role': 'driver', 'driverName': 'Ravi'});
      return (Load.fromDoc(await db.collection('loads').doc('L1').get()), Vehicle.fromDoc(await db.collection('vehicles').doc('v1').get()));
    }

    test('too low and too high are refused with the allowed range and nothing is written', () async {
      final (load, v) = await seed(1000000);
      await expectLater(OfferService.send(load: load, vehicle: v, pricePaise: 100000),
          throwsA(isA<OfferOutOfRangeException>().having((e) => e.tooLow, 'tooLow', true).having((e) => e.minPaise, 'min', 300000).having((e) => e.maxPaise, 'max', 3000000)));
      await expectLater(OfferService.send(load: load, vehicle: v, pricePaise: 4000000), throwsA(isA<OfferOutOfRangeException>().having((e) => e.tooLow, 'tooLow', false)));
      expect((await db.collection('offers').get()).docs, isEmpty);
    });

    test('inside the range works; a load without an estimate has no limit', () async {
      final (load, v) = await seed(1000000);
      expect(await OfferService.send(load: load, vehicle: v, pricePaise: 300000), 'L1_driver1');
      await db.collection('offers').doc('L1_driver1').delete();
      final (plain, v2) = await seed(null);
      expect(await OfferService.send(load: plain, vehicle: v2, pricePaise: 100), 'L1_driver1');
    });
  });

  group('chat repeat guard', () {
    test('isRepeat ignores case, spaces and end punctuation', () {
      expect(ChatService.isRepeat('Hello there', 'hello   there!'), isTrue);
      expect(ChatService.isRepeat('Ok.', 'ok'), isTrue);
      expect(ChatService.isRepeat('Hello', 'Hello again'), isFalse);
      expect(ChatService.isRepeat('', ''), isFalse);
      expect(ChatService.isRepeat('...', '!!!'), isFalse, reason: 'nothing left after the ends are trimmed');
    });

    Future<Booking> seedBooking() async {
      await db.collection('bookings').doc('b1').set({'driverId': 'driver1', 'customerId': 'c1', 'status': 'accepted', 'pickup': 'A', 'drop': 'B', 'createdAt': Timestamp.now()});
      return Booking.fromDoc(await db.collection('bookings').doc('b1').get());
    }

    test('the same text twice in a row is refused; another text, or the other side, is fine', () async {
      final b = await seedBooking();
      await ChatService.send(b, 'On my way');
      await expectLater(ChatService.send(b, '  on my way '), throwsA(isA<ChatSendException>().having((e) => e.reason, 'reason', 'repeat')));
      expect((await db.collection('bookings').doc('b1').collection('messages').get()).docs.length, 1);
      await ChatService.send(b, 'Reached the gate');
      await ChatService.send(b, 'On my way');
      expect((await db.collection('bookings').doc('b1').collection('messages').get()).docs.length, 3);
    });

    test('the other person may send the same words', () async {
      final b = await seedBooking();
      await ChatService.send(b, 'Ok');
      Backend.useFakes(db: db, uid: () => 'c1');
      await ChatService.send(b, 'ok');
      expect((await db.collection('bookings').doc('b1').collection('messages').get()).docs.length, 2);
    });
  });

  group('RatingBurst', () {
    test('5 one-star ratings in 24 hours is a burst; 4 is not; other stars and old ones do not count', () {
      final list = [
        for (var i = 0; i < 5; i++) r('a$i', 'u1', 'x$i', 1, now.subtract(Duration(hours: i))),
        for (var i = 0; i < 4; i++) r('b$i', 'u2', 'x$i', 1, now.subtract(Duration(hours: i))),
        for (var i = 0; i < 6; i++) r('c$i', 'u3', 'x$i', 2, now.subtract(const Duration(hours: 1))),
        for (var i = 0; i < 6; i++) r('d$i', 'u4', 'x$i', 1, now.subtract(const Duration(hours: 30))),
      ];
      final found = RatingBurst.find(list, now);
      expect(found.map((e) => e.raterId), ['u1']);
      expect(found.single.oneStarCount, 5);
      expect(found.single.distinctRated, 5);
      expect(found.single.latest, now);
    });

    test('exactly 24 hours old still counts; the future and missing times do not; biggest first', () {
      final list = [
        for (var i = 0; i < 5; i++) r('a$i', 'u1', 'same', 1, now.subtract(const Duration(hours: 24))),
        for (var i = 0; i < 7; i++) r('b$i', 'u2', 'x$i', 1, now.subtract(const Duration(minutes: 5))),
        r('f1', 'u3', 'x', 1, now.add(const Duration(hours: 1))),
        Rating(id: 'n', bookingId: 'b', raterId: 'u2', ratedId: 'x', stars: 1, comment: ''),
      ];
      final found = RatingBurst.find(list, now);
      expect(found.map((e) => (e.raterId, e.oneStarCount)), [('u2', 7), ('u1', 5)]);
      expect(found.last.distinctRated, 1);
      expect(RatingBurst.find(list, now, minOneStars: 8), isEmpty);
    });
  });

  group('AdminRatingBurstScreen', () {
    testWidgets('lists the burst rater; empty state otherwise', (t) async {
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      Widget host() => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: AdminRatingBurstScreen(now: () => now)));
      await t.pumpWidget(host());
      await settle(t);
      expect(find.text('No one gave 5 or more 1-star ratings in the last 24 hours'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await t.runAsync(() => db.collection('ratings').doc('r$i').set({'bookingId': 'b$i', 'raterId': 'bad1', 'ratedId': 'x$i', 'stars': 1, 'comment': '', 'createdAt': Timestamp.fromDate(now.subtract(Duration(hours: i)))}));
      }
      await t.tap(find.byKey(const ValueKey('burstRefresh')));
      await settle(t);
      expect(find.byKey(const ValueKey('burst_bad1')), findsOneWidget);
      expect(find.text('5 one-star ratings given to 5 people'), findsOneWidget);
    });
  });

  test('staff area: rating bursts for super, support and ops', () {
    for (final role in ['super', 'support', 'ops']) {
      expect(staffCan(role, 'adminRatingBurst'), isTrue, reason: role);
    }
    expect(staffCan('verifier', 'adminRatingBurst'), isFalse);
  });

  test('abuse strings: 12 languages, same placeholders', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in abuseStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
      for (var i = 1; i < 12; i++) {
        expect(ph.allMatches(e.value[i]).map((m) => m[1]).toSet(), want, reason: '${e.key}/$i');
      }
    }
  });
}
