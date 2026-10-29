import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/adapters.dart';
import 'package:transport_app/core/features/features.dart';

/// E4: every outside service has a fake, a switch, a cost guard and an owner sheet; nothing paid runs by default.
void main() {
  /// One fake per ConnectKit id. A new id without a fake fails the first test.
  final fakes = <String, Object>{
    'photo': FakeFileStore(),
    'maps': FakeMapsProvider(),
    'toll': const FakeTollEstimator(),
    'places': const FakePlacesFinder(),
    'push': FakePushGateway(),
    'sms': FakeSmsGateway(),
    'whatsapp': FakeWhatsAppGateway(),
    'payment': FakePaymentGateway(),
    'payout': FakePayoutGateway(),
    'kyc': FakeKycVerifier(),
    'liveness': const FakeLivenessChecker(),
    'ocr': const FakeOcrReader(),
    'translation': const FakeTranslator(),
    'speech': FakeSpeechAdapter(),
    'telemetry': FakeDeviceTelemetry(),
    'insurance': FakeInsuranceQuotes(),
    'credit': const FakeCreditPartnerLinks(),
    'erp': FakeErpWebhooks(),
  };
  final flagsDoc = File('docs/FLAGS.md').readAsStringSync();
  final registered = Features.registry.map((s) => s.key).toSet();

  test('every adapter has a fake, a switch, caps and an owner sheet', () {
    expect(ConnectKit.specs.map((s) => s.id).toSet(), fakes.keys.toSet());
    expect(ConnectKit.specs.map((s) => s.id).toSet().length, ConnectKit.specs.length, reason: 'duplicate id');
    for (final s in ConnectKit.specs) {
      expect(registered.contains(s.flag) || flagsDoc.contains('| `${s.flag}` |'), isTrue, reason: '${s.id}: ${s.flag} is not a known switch');
      expect(s.caps.daily, greaterThan(0));
      expect(s.caps.perUser, inInclusiveRange(1, s.caps.daily));
      final doc = File(s.doc);
      expect(doc.existsSync(), isTrue, reason: s.doc);
      final text = doc.readAsStringSync();
      for (final must in ['## Owner steps', '## Cost guard', 'UNVERIFIED', '`${s.flag}`', 'config/providers.${s.id}']) {
        expect(text, contains(must), reason: '${s.doc} lacks $must');
      }
    }
  });

  test('regulated services are behind legal gates', () {
    for (final id in ['payout', 'insurance', 'credit']) {
      expect(ConnectKit.spec(id).flag, startsWith('legalGate'), reason: id);
    }
  });

  test('the connect sheets hold no key or token', () {
    final bad = RegExp(r'(AIza[0-9A-Za-z_-]{20,}|rzp_(live|test)_[0-9A-Za-z]{8,}|sk_live_|-----BEGIN)');
    for (final s in ConnectKit.specs) {
      expect(bad.hasMatch(File(s.doc).readAsStringSync()), isFalse, reason: s.doc);
    }
  });

  group('selection', () {
    test('by default nothing real is used, for every adapter', () {
      for (final f in [Features.pilotDefault, const Features(pilotMode: false)]) {
        for (final s in ConnectKit.specs) {
          expect(ConnectKit.useReal(s.id, f, const ProviderConfig({})), isFalse, reason: s.id);
          final configured = ProviderConfig({s.id: {'configured': true}});
          expect(ConnectKit.useReal(s.id, f, configured), isFalse, reason: '${s.id}: configured but switch off');
        }
      }
    });

    test('the switch alone is not enough; switch plus configured picks the real one', () {
      const on = Features(flags: {FeatureKey.maps: true});
      expect(ConnectKit.pick<String>('maps', on, const ProviderConfig(), real: () => 'real', fallback: 'none'), 'none');
      final cfg = ProviderConfig.fromMap({
        'maps': {'configured': true},
        'junk': 5,
      });
      expect(ConnectKit.pick<String>('maps', on, cfg, real: () => 'real', fallback: 'none'), 'real');
      expect(ProviderConfig.fromMap(null).configured('maps'), isFalse);
      expect(ProviderConfig.fromMap({'maps': {'configured': 'yes'}}).configured('maps'), isFalse);
    });
  });

  group('cost guard', () {
    test('per-user and daily caps, then a new day resets', () {
      var now = DateTime(2026, 1, 1, 10);
      final g = CostGuard(const CostCaps(daily: 3, perUser: 2), killed: () => false, now: () => now);
      expect(g.take('a'), isNull);
      expect(g.take('a'), isNull);
      expect(g.take('a'), CostDenied.userCap);
      expect(g.take('b'), isNull);
      expect(g.take('c'), CostDenied.dailyCap);
      expect(g.usedToday, 3);
      now = DateTime(2026, 1, 2, 0, 1);
      expect(g.take('a'), isNull);
      expect(g.usedToday, 1);
    });

    test('the kill switch wins, and the adapter flag is its kill switch', () {
      var f = const Features(flags: {FeatureKey.smsGateway: true});
      final g = ConnectKit.guard('sms', () => f, const ProviderConfig());
      expect(g.take('u'), isNull);
      f = f.withFlag(FeatureKey.smsGateway, false);
      expect(g.take('u'), CostDenied.killed);
    });

    test('config can lower the caps but never raise them; junk is ignored', () {
      const caps = CostCaps(daily: 100, perUser: 10);
      expect(caps.lowered({'daily': 50, 'perUser': 5}).daily, 50);
      expect(caps.lowered({'daily': 50, 'perUser': 5}).perUser, 5);
      expect(caps.lowered({'daily': 5000, 'perUser': 999}).daily, 100);
      expect(caps.lowered({'daily': 5000, 'perUser': 999}).perUser, 10);
      expect(caps.lowered({'daily': 'x', 'perUser': -1}).perUser, 10);
      expect(caps.lowered({'daily': 4}).perUser, 4, reason: 'per user never above daily');
      expect(caps.lowered(null).daily, 100);
    });
  });

  group('safe defaults never call out and never throw', () {
    const p = GeoPoint2(28.6, 77.2);
    test('No... adapters answer calmly', () async {
      expect(await const NoTollEstimator().tollPaise(p, p, axles: 2), isNull);
      expect(await const NoPlacesFinder().nearby(p, PlaceKind.fuel), isEmpty);
      expect((await const NoWhatsAppGateway().sendTemplate('+919876543210', 't', [])).failure, ConnectFailure.notConfigured);
      expect((await const NoPayoutGateway().payout(100, 'b', 'k')).failure, ConnectFailure.notConfigured);
      expect(await const NoLivenessChecker().check(Uint8List(1)), LivenessStatus.unavailable);
      expect(await const NoOcrReader().read(Uint8List(1), OcrKind.rc), isEmpty);
      expect(await const NoTranslator().translate('x', from: 'hi', to: 'en'), isNull);
      expect(await const NoSpeechAdapter().speak('x', 'hi'), isFalse);
      expect(await const NoDeviceTelemetry().latest('d'), isNull);
      expect((await const NoInsuranceQuotes().requestQuote(cargoValuePaise: 1, goods: 'g', bookingId: 'b')).failure, ConnectFailure.notConfigured);
      expect(const NoCreditPartnerLinks().linkFor(CreditLinkKind.fastag), isNull);
      expect((await const NoErpWebhooks().deliver('load.created', {})).failure, ConnectFailure.notConfigured);
    });
  });

  group('fakes keep the contract', () {
    test('toll is whole paise and grows with axles; bad axles give null', () async {
      const a = GeoPoint2(28.6, 77.2), b = GeoPoint2(19.0, 72.8);
      final two = await const FakeTollEstimator().tollPaise(a, b, axles: 2);
      final six = await const FakeTollEstimator().tollPaise(a, b, axles: 6);
      expect(two, isA<int>());
      expect(six!, greaterThan(two!));
      expect(await const FakeTollEstimator().tollPaise(a, b, axles: 1), isNull);
    });

    test('places are bounded and filtered by kind and radius', () async {
      final many = [for (var i = 0; i < 50; i++) PlaceHit('p$i', PlaceKind.fuel, GeoPoint2(28.6 + i * 0.0001, 77.2))];
      final f = FakePlacesFinder([...many, const PlaceHit('far', PlaceKind.fuel, GeoPoint2(20, 70)), const PlaceHit('d', PlaceKind.dhaba, GeoPoint2(28.6, 77.2))]);
      final hits = await f.nearby(const GeoPoint2(28.6, 77.2), PlaceKind.fuel);
      expect(hits.length, maxPlaces);
      expect(hits.any((h) => h.name == 'far' || h.kind != PlaceKind.fuel), isFalse);
    });

    test('a payout retried with the same key pays once; bad amounts are refused', () async {
      final g = FakePayoutGateway();
      expect((await g.payout(5000, 'ben1', 'k1')).ok, isTrue);
      expect((await g.payout(9000, 'ben1', 'k1')).ok, isTrue);
      expect(g.paid, {'k1': 5000});
      expect((await g.payout(0, 'ben1', 'k2')).failure, ConnectFailure.invalidInput);
      expect((await g.payout(-5, 'ben1', 'k3')).failure, ConnectFailure.invalidInput);
    });

    test('whatsapp needs E.164 and a template; erp needs a dotted event name', () async {
      expect((await FakeWhatsAppGateway().sendTemplate('98765', 't', [])).failure, ConnectFailure.invalidInput);
      expect((await FakeWhatsAppGateway().sendTemplate('+919876543210', '', [])).failure, ConnectFailure.invalidInput);
      expect((await FakeErpWebhooks().deliver('Load Created', {})).failure, ConnectFailure.invalidInput);
      expect((await FakeErpWebhooks().deliver('load.created', {'id': 'x'})).ok, isTrue);
    });

    test('credit links are https only', () {
      const f = FakeCreditPartnerLinks({CreditLinkKind.fastag: 'http://x.example', CreditLinkKind.fuelCard: 'https://fuel.example/apply'});
      expect(f.linkFor(CreditLinkKind.fastag), isNull);
      expect(f.linkFor(CreditLinkKind.fuelCard)!.host, 'fuel.example');
      expect(f.linkFor(CreditLinkKind.driverAdvance), isNull);
    });

    test('insurance is a quote request only and checks input', () async {
      final q = FakeInsuranceQuotes();
      expect((await q.requestQuote(cargoValuePaise: 0, goods: 'x', bookingId: 'b')).failure, ConnectFailure.invalidInput);
      expect((await q.requestQuote(cargoValuePaise: 100000, goods: 'rice', bookingId: 'b')).ok, isTrue);
    });

    test('ocr, liveness, translation and speech fakes', () async {
      expect(await const FakeOcrReader({OcrKind.plate: {'plate': 'MH12AB1234'}}).read(Uint8List(1), OcrKind.plate), {'plate': 'MH12AB1234'});
      expect(await const FakeOcrReader().read(Uint8List(0), OcrKind.plate), isEmpty);
      expect(await const FakeLivenessChecker().check(Uint8List(0)), LivenessStatus.notLive);
      expect(await const FakeTranslator().translate('x' * 1001, from: 'hi', to: 'en'), isNull);
      final s = FakeSpeechAdapter(heard: 'haan');
      expect(await s.speak('naya load', 'hi'), isTrue);
      expect(await s.listen('hi'), 'haan');
    });
  });
}
