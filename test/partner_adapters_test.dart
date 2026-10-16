import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/adapters.dart';
import 'package:transport_app/core/adapters/partner_adapters.dart';
import 'package:transport_app/core/services/server_actions.dart';

class Fake implements ServerGateway {
  Object? error;
  Map<String, dynamic> answer = {};
  final calls = <(String, Map<String, Object?>)>[];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data) async {
    calls.add((name, data));
    if (error != null) throw error!;
    return answer;
  }
}

/// F35: MSG91 and KYC partner skeletons fall back calmly.
void main() {
  group('Msg91SmsGateway', () {
    test('numbers must be E.164 and the text sensible before anything is sent', () async {
      final f = Fake();
      final g = Msg91SmsGateway(f);
      expect((await g.send('9876543210', 'hi')).failure, SmsFailure.invalidNumber);
      expect((await g.send('+919876543210', '  ')).failure, SmsFailure.providerError);
      expect((await g.send('+919876543210', 'x' * 481)).failure, SmsFailure.providerError);
      expect(f.calls, isEmpty);
    });

    test('a message id means sent; no function is notConfigured; too many is rateLimited; no crash', () async {
      final f = Fake()..answer = {'messageId': 'm1'};
      final g = Msg91SmsGateway(f);
      final ok = await g.send('+919876543210', 'I am safe');
      expect((ok.ok, ok.messageId), (true, 'm1'));
      f.answer = {};
      expect((await g.send('+919876543210', 'x')).failure, SmsFailure.providerError);
      f.error = FirebaseFunctionsException(code: 'not-found', message: 'no function');
      expect((await g.send('+919876543210', 'x')).failure, SmsFailure.notConfigured);
      f.error = FirebaseFunctionsException(code: 'resource-exhausted', message: 'limit');
      expect((await g.send('+919876543210', 'x')).failure, SmsFailure.rateLimited);
      f.error = Exception('offline');
      expect((await g.send('+919876543210', 'x')).failure, SmsFailure.notConfigured);
    });

    test('login codes are not done by this partner', () async {
      final g = Msg91SmsGateway(Fake());
      expect((await g.startOtp('+919876543210')).failure, SmsFailure.notConfigured);
      expect(await g.verifyOtp('c', '123456'), isFalse);
    });
  });

  group('PartnerKycVerifier', () {
    test('answers map to the typed status; numbers are tidied before they are sent', () async {
      final f = Fake();
      final k = PartnerKycVerifier(f);
      f.answer = {'status': 'verified', 'holderName': ' Ramesh Kumar '};
      final a = await k.verify(KycKind.licence, ' dl04 2011-0012345 ');
      expect((a.status, a.holderName), (KycStatus.verified, ' Ramesh Kumar '));
      expect(f.calls.single.$2, {'kind': 'licence', 'number': 'DL0420110012345'});
      f.answer = {'status': 'mismatch', 'holderName': 'Other'};
      expect((await k.verify(KycKind.pan, 'ABCDE1234F')).status, KycStatus.mismatch);
      f.answer = {'status': 'not_found'};
      expect((await k.verify(KycKind.gstin, '27ABCDE1234F1Z5')).status, KycStatus.notFound);
      f.answer = {'status': 'something new'};
      expect((await k.verify(KycKind.rc, 'MH12AB1234')).status, KycStatus.unavailable);
    });

    test('Aadhaar is never sent, an empty number is not found, a missing server is unavailable', () async {
      final f = Fake();
      final k = PartnerKycVerifier(f);
      expect((await k.verify(KycKind.aadhaar, '123412341234')).status, KycStatus.unavailable);
      expect((await k.verify(KycKind.pan, '  ')).status, KycStatus.notFound);
      expect(f.calls, isEmpty);
      f.error = FirebaseFunctionsException(code: 'not-found', message: 'x');
      expect((await k.verify(KycKind.licence, 'DL0420110012345')).status, KycStatus.unavailable);
      f.error = Exception('offline');
      expect((await k.verify(KycKind.licence, 'DL0420110012345')).status, KycStatus.unavailable);
    });
  });
}
