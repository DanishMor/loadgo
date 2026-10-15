import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/trip_otp_attempts.dart';

/// F2: the trip code counter. The rules side is in firestore_rules_test.
void main() {
  final now = DateTime(2026, 1, 1, 12);
  Map<String, dynamic> doc(int count, DateTime at) => {'count': count, 'guess': '111111', 'guessAt': Timestamp.fromDate(at), 'actorId': 'd'};

  test('no document: the first guess counts 1; each guess adds one', () {
    expect(TripOtpAttempts.nextCount(null, now), 1);
    expect(TripOtpAttempts.nextCount(doc(1, now), now), 2);
    expect(TripOtpAttempts.nextCount(doc(4, now), now), 5);
  });

  test('the 5th guess locks for 15 minutes from guessAt, then counting restarts', () {
    final locked = doc(5, now.subtract(const Duration(minutes: 5)));
    expect(TripOtpAttempts.lockRemaining(locked, now), const Duration(minutes: 10));
    expect(TripOtpAttempts.lockRemaining(doc(4, now), now), isNull, reason: '4 is not locked');
    final old = doc(5, now.subtract(const Duration(minutes: 16)));
    expect(TripOtpAttempts.lockRemaining(old, now), isNull);
    expect(TripOtpAttempts.nextCount(old, now), 1);
  });

  test('odd stored data never crashes and never locks', () {
    for (final d in <Map<String, dynamic>?>[
      null,
      {},
      {'count': 'x', 'guessAt': 5},
      {'count': 9999999999999, 'guessAt': 'now'},
      {'count': -3, 'guessAt': Timestamp.fromDate(now)},
    ]) {
      expect(() => TripOtpAttempts.lockRemaining(d, now), returnsNormally);
      expect(TripOtpAttempts.lockRemaining(d, now), isNull);
      expect(() => TripOtpAttempts.nextCount(d, now), returnsNormally);
    }
    expect(TripOtpAttempts.nextCount({'count': -3}, now), 1);
  });

  test('GuessState: attempts left count down and are 0 when locked', () {
    expect(const GuessState(1, null).attemptsLeft, 4);
    expect(const GuessState(4, null).attemptsLeft, 1);
    expect(const GuessState(5, Duration(minutes: 15)).attemptsLeft, 0);
  });

  test('policy numbers: 5 guesses, 15 minutes (same as the rules)', () {
    expect(TripOtpAttempts.maxAttempts, 5);
    expect(TripOtpAttempts.lockMinutes, 15);
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules.contains('d.count <= 5'), isTrue);
    expect(rules.contains("duration.value(15, 'm')"), isTrue);
  });

  test('five stored guesses lock the entry and write one audit line; a locked entry refuses more', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'driver1');
    await db.collection('bookings').doc('B1').set({'customerId': 'customer1', 'driverId': 'driver1'});
    for (var i = 1; i <= 4; i++) {
      final g = await TripOtpAttempts.recordGuess('B1', 'pickup', '11111$i');
      expect(g.count, i);
      expect(g.attemptsLeft, 5 - i);
      expect(g.lockedFor, isNull);
    }
    expect((await db.collection('audit_events').get()).docs, isEmpty);
    final last = await TripOtpAttempts.recordGuess('B1', 'pickup', '111115');
    expect(last.lockedFor, const Duration(minutes: 15));
    final audit = (await db.collection('audit_events').get()).docs.single.data();
    expect(audit['type'], 'otp_lock');
    expect(audit['bookingId'], 'B1');
    expect(audit['targetId'], 'customer1');
    await expectLater(TripOtpAttempts.recordGuess('B1', 'pickup', '111116'), throwsA(isA<OtpLockedException>()));
    // Delivery has its own counter.
    expect((await TripOtpAttempts.recordGuess('B1', 'delivery', '222222')).count, 1);
    final stored = (await db.collection('bookings').doc('B1').collection('otp_attempts').doc('pickup').get()).data()!;
    expect(stored['count'], 5);
    expect(stored.keys.toSet(), {'count', 'guess', 'guessAt', 'actorId'});
  });

  group('guards: a redesign cannot drop the limit', () {
    String src(String p) => File(p).readAsStringSync();
    test('the booking step stores the guess first and resets it in the same transaction', () {
      final s = src('lib/core/services/booking_service.dart');
      expect(s.contains('TripOtpAttempts.recordGuess'), isTrue);
      expect(s.contains("'count': 0"), isTrue);
    });
    test('the rules need a stored, counted guess for pickup and delivery', () {
      final r = src('firestore.rules');
      expect(r.contains("guessCommitted(bookingId, 'pickup')"), isTrue);
      expect(r.contains("guessCommitted(bookingId, 'delivery')"), isTrue);
    });
    test('the driver screen tells about the lock and the customer card shows the notice', () {
      expect(src('lib/driver/driver_trip_screen.dart').contains('OtpLockedException'), isTrue);
      expect(src('lib/customer/trip_otp_card.dart').contains('tripOtpLockNotice'), isTrue);
    });
    test('the messages exist in 12 languages', () {
      for (final k in ['tripOtpLockedMin', 'tripOtpLockNotice', 'otpAttemptsLeft']) {
        for (final l in AppLanguage.values) {
          expect(T.get(k, l).trim(), isNotEmpty, reason: '$k ${l.name}');
        }
      }
    });
  });
}
