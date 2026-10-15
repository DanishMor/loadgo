import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/security/otp_limits.dart';

class MemStore implements OtpLimitStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
}

/// F1: login code limits, plus guards so a UI refactor cannot remove them.
void main() {
  const phone = '9876543210';
  late MemStore store;
  late DateTime clock;
  late OtpLimiter lim;

  setUp(() {
    store = MemStore();
    clock = DateTime(2026, 1, 1, 10);
    lim = OtpLimiter(store: store, now: () => clock);
  });

  test('the policy numbers are what the plan says', () {
    expect(OtpPolicy.resendSeconds, 60);
    expect(OtpPolicy.sendsPerHour, 5);
    expect(OtpPolicy.maxWrongAttempts, 5);
    expect(OtpPolicy.lockMinutes, 15);
  });

  test('the 6th code within an hour is refused, and frees up when the first is an hour old', () async {
    for (var i = 0; i < 5; i++) {
      expect(await lim.sendBlockedFor(phone), isNull, reason: 'send $i');
      await lim.recordSend(phone);
      clock = clock.add(const Duration(minutes: 1));
    }
    final wait = await lim.sendBlockedFor(phone);
    expect(wait, isNotNull);
    expect(wait!.inMinutes, 55); // first send was 5 minutes ago
    clock = clock.add(const Duration(minutes: 55));
    expect(await lim.sendBlockedFor(phone), isNull);
  });

  test('another number is not affected', () async {
    for (var i = 0; i < 5; i++) {
      await lim.recordSend(phone);
    }
    expect(await lim.sendBlockedFor(phone), isNotNull);
    expect(await lim.sendBlockedFor('9123456780'), isNull);
  });

  test('4 wrong codes count down, the 5th locks for 15 minutes, then it opens', () async {
    for (var left = 4; left >= 1; left--) {
      final f = await lim.recordWrong(phone);
      expect(f.attemptsLeft, left);
      expect(f.lockedFor, isNull);
    }
    final f = await lim.recordWrong(phone);
    expect(f.lockedFor, const Duration(minutes: 15));
    expect(await lim.lockedFor(phone), isNotNull);
    expect(await lim.sendBlockedFor(phone), isNotNull, reason: 'a locked number cannot ask for new codes either');
    clock = clock.add(const Duration(minutes: 16));
    expect(await lim.lockedFor(phone), isNull);
    expect((await lim.recordWrong(phone)).attemptsLeft, 4, reason: 'counting starts again');
  });

  test('a correct code clears the wrong-code count but not the send count', () async {
    await lim.recordWrong(phone);
    await lim.recordWrong(phone);
    await lim.recordSend(phone);
    await lim.recordSuccess(phone);
    expect((await lim.recordWrong(phone)).attemptsLeft, 4);
    final raw = store.map[OtpLimiter.keyFor(phone)]!;
    expect(raw.contains('"s":[1'), isTrue);
  });

  test('the number itself is never stored, and broken stored data does not crash', () async {
    await lim.recordSend(phone);
    expect(store.map.keys.single.contains(phone), isFalse);
    expect(store.map.values.single.contains(phone), isFalse);
    store.map[OtpLimiter.keyFor(phone)] = '{not json';
    expect(await lim.sendBlockedFor(phone), isNull);
    store.map[OtpLimiter.keyFor(phone)] = '{"s":"x","w":"y","l":null}';
    expect(await lim.lockedFor(phone), isNull);
  });

  test('minutesLeft rounds up and is never zero', () {
    expect(minutesLeft(const Duration(seconds: 1)), 1);
    expect(minutesLeft(const Duration(minutes: 14, seconds: 1)), 15);
    expect(minutesLeft(Duration.zero), 1);
  });

  test('all new messages exist in all 12 languages', () {
    for (final k in ['otpSendCap', 'otpLockedMin', 'otpAttemptsLeft', 'tripOtpLockedMin', 'tripOtpLockNotice']) {
      for (final l in AppLanguage.values) {
        expect(T.get(k, l).trim(), isNotEmpty, reason: '$k ${l.name}');
      }
    }
  });

  group('guards: the limits are wired in and a redesign cannot drop them', () {
    String src(String p) => File(p).readAsStringSync();

    test('every code send goes through the limiter', () {
      final s = src('lib/core/services/auth_helpers.dart');
      expect(s.contains('sendBlockedFor'), isTrue);
      expect(s.contains('recordSend'), isTrue);
      expect(s.contains("'otpSendCap'"), isTrue);
    });

    test('the code screen counts wrong codes, locks, and uses the 60 second cooldown', () {
      final s = src('lib/auth/otp_verification_screen.dart');
      expect(s.contains('recordWrong'), isTrue);
      expect(s.contains('lockedFor'), isTrue);
      expect(s.contains('OtpPolicy.resendSeconds'), isTrue);
      expect(s.contains('OtpResendButton'), isTrue);
    });
  });
}
