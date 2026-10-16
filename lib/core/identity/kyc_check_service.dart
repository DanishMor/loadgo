import '../adapters/kyc_adapter.dart';
import '../adapters/partner_adapters.dart';
import '../features/features.dart';
import '../services/features_service.dart';
import 'kyc_validators.dart';

/// G13: after a driver saves their papers, ask the ID check for each number. The server stores the answers
/// for the admin (`kyc_checks/{uid}`); this class only asks. Behind the `kycVerify` switch (OFF). With the
/// switch off, or no partner, or any problem, nothing changes: the format check and the admin's look at the
/// papers stay the way it is checked. Never throws. The full Aadhaar number is never held: only its last four digits.
class KycCheckService {
  KycCheckService._();

  static KycVerifier verifier = PartnerKycVerifier();

  /// Numbers asked about, by kind. Returns how many got a real answer.
  static Future<int> checkDriver(DriverKyc kyc) async {
    if (!FeaturesService.isOn(FeatureKey.kycVerify)) return 0;
    var answered = 0;
    final asks = <KycKind, String>{
      KycKind.licence: kyc.dlNumber,
      KycKind.rc: kyc.rcNumber,
      KycKind.pan: kyc.pan,
      KycKind.aadhaar: kyc.aadhaarLast4,
    };
    for (final e in asks.entries) {
      if (e.value.isEmpty) continue;
      try {
        final r = await verifier.verify(e.key, e.value);
        if (r.status != KycStatus.unavailable) answered++;
      } catch (_) {}
    }
    return answered;
  }
}
