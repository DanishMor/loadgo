import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/adapters.dart';

/// MASTER-6 Task 46: the contract every provider must meet. A real provider is
/// added to the lists below and must pass the same tests as the fake.
void main() {
  group('SmsGateway', () {
    final makers = <String, SmsGateway Function()>{'fake': FakeSmsGateway.new};
    makers.forEach((name, make) {
      test('$name: sends to E.164 numbers only; limits per number', () async {
        final g = make();
        expect((await g.send('+919876543210', 'hi')).ok, isTrue);
        expect((await g.send('9876543210', 'hi')).failure, SmsFailure.invalidNumber);
        expect((await g.send('+91 98765', 'hi')).failure, SmsFailure.invalidNumber);
        SmsResult last = const SmsResult.sent('x');
        for (var i = 0; i < 10; i++) {
          last = await g.send('+919800000001', 'hi');
        }
        expect(last.failure, SmsFailure.rateLimited);
      });
      test('$name: a one-time code works once, is wrong for a bad code, and stops after 5 tries', () async {
        final g = make() as FakeSmsGateway;
        final s = await g.startOtp('+919876543210');
        expect(s.ok, isTrue);
        final code = g.codeFor(s.challengeId!)!;
        expect(await g.verifyOtp(s.challengeId!, '000000'), isFalse);
        expect(await g.verifyOtp(s.challengeId!, code), isTrue);
        expect(await g.verifyOtp(s.challengeId!, code), isFalse, reason: 'a code is single use');
        final t = await g.startOtp('+919876543210');
        for (var i = 0; i < 5; i++) {
          await g.verifyOtp(t.challengeId!, '111111');
        }
        expect(await g.verifyOtp(t.challengeId!, g.codeFor(t.challengeId!)!), isFalse, reason: 'locked after 5 wrong tries');
        expect((await g.startOtp('12345')).failure, SmsFailure.invalidNumber);
      });
    });
    test('the default sends nothing and says so', () async {
      const g = NoSmsGateway();
      expect((await g.send('+919876543210', 'x')).failure, SmsFailure.notConfigured);
      expect((await g.startOtp('+919876543210')).failure, SmsFailure.notConfigured);
      expect(await g.verifyOtp('c', '1'), isFalse);
    });
  });

  group('PushGateway', () {
    test('fake: delivers, reports bad tokens, refuses more than 500', () async {
      final g = FakePushGateway()..invalid.add('dead');
      final r = await g.send(['a', 'dead', ''], const PushMessage(title: 't', body: 'b'));
      expect(r.delivered, 1);
      expect(r.badTokens, ['dead', '']);
      expect(() => g.send(List.filled(501, 'x'), const PushMessage(title: 't', body: 'b')), throwsArgumentError);
    });
    test('the default delivers nothing', () async {
      expect((await const NoPushGateway().send(['a'], const PushMessage(title: 't', body: 'b'))).delivered, 0);
    });
  });

  group('MapsProvider', () {
    test('fake: finds known places, null for unknown; a route has distance and time', () async {
      final m = FakeMapsProvider();
      final d = await m.geocode(' Delhi ');
      final b = await m.geocode('mumbai');
      expect(d, isNotNull);
      expect(await m.geocode('nowhere'), isNull);
      final r = (await m.route(d!, b!))!;
      expect(r.meters, greaterThan(1000 * 1000));
      expect(r.seconds, greaterThan(0));
      expect((await m.route(d, d))!.meters, 0);
    });
    test('the default finds nothing and does not throw', () async {
      expect(await const NoMapsProvider().geocode('delhi'), isNull);
      expect(await const NoMapsProvider().route(const GeoPoint2(0, 0), const GeoPoint2(1, 1)), isNull);
    });
  });

  group('PaymentGateway', () {
    final makers = <String, PaymentGateway Function()>{'fake': FakePaymentGateway.new};
    makers.forEach((name, make) {
      test('$name: whole positive paise only, up to 1 crore rupees', () async {
        final g = make();
        for (final bad in [0, -5, maxOrderPaise + 1]) {
          expect((await g.createOrder(bad, 'B1')).$2, PaymentFailure.invalidAmount, reason: '$bad');
        }
        final ok = await g.createOrder(250000, 'B1');
        expect(ok.$1!.amountPaise, 250000);
        expect(ok.$1!.reference, 'B1');
      });
      test('$name: a wrong signature or unknown order is refused', () async {
        final g = make();
        final o = (await g.createOrder(100000, 'B1')).$1!;
        expect((await g.verify(o.id, 'p1', 'forged')).failure, PaymentFailure.badSignature);
        expect((await g.verify('nope', 'p1', 'x')).failure, PaymentFailure.unknownOrder);
        expect((await g.verify(o.id, 'p1', FakePaymentGateway.signatureFor(o.id, 'p1'))).ok, isTrue);
      });
      test('$name: refunds add up to at most what was paid', () async {
        final g = make();
        final o = (await g.createOrder(100000, 'B1')).$1!;
        await g.verify(o.id, 'p1', FakePaymentGateway.signatureFor(o.id, 'p1'));
        expect((await g.refund('p1', 40000)).ok, isTrue);
        expect((await g.refund('p1', 70000)).failure, PaymentFailure.refundTooLarge);
        expect((await g.refund('p1', 60000)).ok, isTrue);
        expect((await g.refund('p1', 1)).failure, PaymentFailure.alreadyRefunded);
        expect((await g.refund('p1', 0)).failure, anyOf(PaymentFailure.invalidAmount, PaymentFailure.alreadyRefunded));
        expect((await g.refund('unknown', 100)).failure, PaymentFailure.unknownOrder);
      });
    });
    test('the default creates and verifies nothing', () async {
      const g = NoPaymentGateway();
      expect((await g.createOrder(100, 'B1')).$2, PaymentFailure.notConfigured);
      expect((await g.refund('p', 100)).failure, PaymentFailure.notConfigured);
    });
  });

  group('KycVerifier', () {
    test('fake: verified with the holder name, mismatch flagged, unknown not found, spaces and case ignored', () async {
      final k = FakeKycVerifier()..mismatching.add('MH1220200000001');
      k.records['MH1220200000001'] = 'Someone Else';
      final a = await k.verify(KycKind.licence, 'dl04 2011 0012345');
      expect((a.status, a.holderName), (KycStatus.verified, 'Ramesh Kumar'));
      expect((await k.verify(KycKind.licence, 'MH1220200000001')).status, KycStatus.mismatch);
      expect((await k.verify(KycKind.pan, 'ZZZZZ9999Z')).status, KycStatus.notFound);
      expect((await k.verify(KycKind.pan, '  ')).status, KycStatus.notFound);
    });
    test('the default says unavailable, so the app falls back to format checks and admin review', () async {
      expect((await const NoKycVerifier().verify(KycKind.rc, 'MH12AB1234')).status, KycStatus.unavailable);
    });
  });

  group('FileStore', () {
    final makers = <String, FileStore Function()>{'fake': FakeFileStore.new};
    makers.forEach((name, make) {
      test('$name: images under 5 MB at safe paths; the same limits as storage.rules', () async {
        final s = make();
        final img = Uint8List(1000);
        expect((await s.put('users/u1/rc/a.jpg', img, 'image/jpeg')).$1!.bytes, 1000);
        expect((await s.put('users/u1/rc/a.pdf', img, 'application/pdf')).$2, StorageFailure.wrongType);
        expect((await s.put('users/u1/rc/b.jpg', Uint8List(maxUploadBytes + 1), 'image/png')).$2, StorageFailure.tooLarge);
        expect((await s.put('users/u1/rc/b.jpg', Uint8List(maxUploadBytes), 'image/png')).$1, isNotNull);
        for (final bad in ['', '/abs', 'users/../x', 'a//b', 'x' * 201]) {
          expect((await s.put(bad, img, 'image/jpeg')).$2, StorageFailure.badPath, reason: bad);
        }
        expect(await s.delete('users/u1/rc/a.jpg'), isNull);
        expect(await s.delete('users/u1/rc/a.jpg'), StorageFailure.notFound);
      });
    });
    test('the default stores nothing', () async {
      expect((await const NoFileStore().put('a/b.jpg', Uint8List(1), 'image/jpeg')).$2, StorageFailure.notConfigured);
    });
  });
}
