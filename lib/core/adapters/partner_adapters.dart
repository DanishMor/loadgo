import 'package:cloud_functions/cloud_functions.dart';

import '../services/server_actions.dart';
import 'kyc_adapter.dart';
import 'sms_adapter.dart';

/// F35: skeletons for the two partners that are still manual today.
///
/// Both go through Cloud Functions (`smsSend`, `kycVerify`) because the partner
/// key must live on the server. Those functions are not written yet: until they are
/// deployed (and the owner has a partner contract) every call answers
/// "not configured" / "unavailable", and the app keeps doing what it does today:
/// Firebase Auth phone sign-in, format checks, and an admin who looks at the papers.
/// Nothing here may be the only way to do a thing.

/// MSG91 (or another DLT-registered provider) for emergency-contact SMS.
/// Login codes stay with Firebase Auth; [startOtp] / [verifyOtp] are not used with this partner.
class Msg91SmsGateway implements SmsGateway {
  final ServerGateway server;
  Msg91SmsGateway([ServerGateway? server]) : server = server ?? ServerActions.gateway;

  @override
  Future<SmsResult> send(String toE164, String text) async {
    if (!isE164(toE164)) return const SmsResult.failed(SmsFailure.invalidNumber);
    if (text.trim().isEmpty || text.length > 480) return const SmsResult.failed(SmsFailure.providerError);
    try {
      final r = await server.call('smsSend', {'to': toE164, 'text': text});
      final id = r['messageId'];
      return id is String && id.isNotEmpty ? SmsResult.sent(id) : const SmsResult.failed(SmsFailure.providerError);
    } on FirebaseFunctionsException catch (e) {
      return SmsResult.failed(e.code == 'resource-exhausted' ? SmsFailure.rateLimited : SmsFailure.notConfigured);
    } catch (_) {
      return const SmsResult.failed(SmsFailure.notConfigured);
    }
  }

  @override
  Future<OtpStart> startOtp(String toE164) async => const OtpStart.failed(SmsFailure.notConfigured);

  @override
  Future<bool> verifyOtp(String challengeId, String code) async => false;
}

/// A KYC partner for licence, RC, PAN and GSTIN. Aadhaar is never sent to a partner by this app.
/// "Unavailable" means: use the format check and the admin review (the default path).
class PartnerKycVerifier implements KycVerifier {
  final ServerGateway server;
  PartnerKycVerifier([ServerGateway? server]) : server = server ?? ServerActions.gateway;

  @override
  Future<KycResult> verify(KycKind kind, String number) async {
    if (kind == KycKind.aadhaar) return const KycResult(KycStatus.unavailable);
    final n = number.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (n.isEmpty) return const KycResult(KycStatus.notFound);
    try {
      final r = await server.call('kycVerify', {'kind': kind.name, 'number': n});
      final holder = r['holderName'];
      final name = holder is String && holder.trim().isNotEmpty ? holder : null;
      switch (r['status']) {
        case 'verified':
          return KycResult(KycStatus.verified, name);
        case 'mismatch':
          return KycResult(KycStatus.mismatch, name);
        case 'not_found':
          return const KycResult(KycStatus.notFound);
        default:
          return const KycResult(KycStatus.unavailable);
      }
    } catch (_) {
      return const KycResult(KycStatus.unavailable);
    }
  }
}
