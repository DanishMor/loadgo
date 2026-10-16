import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/sms_adapter.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/safety_service.dart';

class _Sms implements SmsGateway {
  final sent = <(String, String)>[];
  bool fail = false;
  @override
  Future<SmsResult> send(String toE164, String text) async {
    sent.add((toE164, text));
    if (fail) throw StateError('down');
    return const SmsResult.sent('m1');
  }

  @override
  Future<OtpStart> startOtp(String toE164) async => const OtpStart.failed(SmsFailure.notConfigured);
  @override
  Future<bool> verifyOtp(String challengeId, String code) async => false;
}

void main() {
  late _Sms sms;
  late FakeFirebaseFirestore db;

  setUp(() {
    sms = _Sms();
    SafetyService.sms = sms;
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.smsGateway: true});
  });
  tearDown(() {
    FeaturesService.reset();
    SafetyService.sms = SafetyService.sms;
  });

  test('numbers a person types become +91 numbers, others are dropped', () {
    expect(SafetyService.e164India('98765 43210'), '+919876543210');
    expect(SafetyService.e164India('+91-98765-43210'), '+919876543210');
    expect(SafetyService.e164India('919876543210'), '+919876543210');
    for (final bad in ['12345', '0987654321', '+14155550123', '', 'abc']) {
      expect(SafetyService.e164India(bad), isNull, reason: bad);
    }
  });

  test('SOS texts every valid saved contact, never throws, and does nothing with the switch off', () async {
    await db.collection('users').doc('u1').set({
      'emergencyContacts': [
        {'name': 'A', 'phone': '9811111111'},
        {'name': 'B', 'phone': 'bad'},
        {'name': 'C', 'phone': '+919822222222'},
      ],
    });
    final id = await SafetyService.sendSos(location: const GeoPoint(28.6139, 77.209));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(id, isNotEmpty);
    expect(sms.sent.map((e) => e.$1), ['+919811111111', '+919822222222']);
    expect(sms.sent.first.$2, contains('28.6139,77.2090'));

    sms.sent.clear();
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.smsGateway: false});
    await SafetyService.sendSos();
    await Future<void>.delayed(Duration.zero);
    expect(sms.sent, isEmpty);
  });

  test('a failing SMS partner does not stop the SOS alert', () async {
    sms.fail = true;
    await db.collection('users').doc('u1').set({'emergencyContacts': [{'name': 'A', 'phone': '9811111111'}]});
    final id = await SafetyService.sendSos();
    await Future<void>.delayed(Duration.zero);
    expect((await db.collection('sos_alerts').doc(id).get()).exists, isTrue);
  });
}
