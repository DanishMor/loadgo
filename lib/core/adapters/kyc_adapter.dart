enum KycKind { licence, rc, pan, gstin, aadhaar }

enum KycStatus { verified, mismatch, notFound, unavailable }

class KycResult {
  final KycStatus status;

  /// Name the government record carries, for the admin to compare. Never
  /// stored beyond the verification note.
  final String? holderName;
  const KycResult(this.status, [this.holderName]);
}

/// LATER(paid): a verification partner (licence, RC, PAN, GSTIN, Aadhaar
/// offline check). Today the app only checks the FORMAT of each number and
/// admins review documents by eye (docs/PAID_UPGRADE_PLAN.md step 6).
abstract class KycVerifier {
  Future<KycResult> verify(KycKind kind, String number);
}

class NoKycVerifier implements KycVerifier {
  const NoKycVerifier();
  @override
  Future<KycResult> verify(KycKind kind, String number) async => const KycResult(KycStatus.unavailable);
}

class FakeKycVerifier implements KycVerifier {
  /// number -> holder name; anything else is "not found"; a number in
  /// [mismatching] is found but flagged.
  final Map<String, String> records = {'DL0420110012345': 'Ramesh Kumar', 'ABCDE1234F': 'Asha Traders'};
  final Set<String> mismatching = {};

  @override
  Future<KycResult> verify(KycKind kind, String number) async {
    final n = number.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (n.isEmpty) return const KycResult(KycStatus.notFound);
    if (mismatching.contains(n)) return KycResult(KycStatus.mismatch, records[n]);
    final name = records[n];
    return name == null ? const KycResult(KycStatus.notFound) : KycResult(KycStatus.verified, name);
  }
}
