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

/// A fixed-rule stand-in for a partner (G13), the same rules as the server's sandbox provider in
/// `functions/src/kyc.js`: the last character decides. `0` = not found, `9` or `Z` = mismatch,
/// anything else = verified with a made-up name. Aadhaar is accepted as its last four digits only
/// and nothing is looked up for it. It never calls out.
class SandboxKycVerifier implements KycVerifier {
  const SandboxKycVerifier();

  static final _format = <KycKind, RegExp>{
    KycKind.licence: RegExp(r'^[A-Z]{2}[0-9]{2}[0-9]{4}[0-9]{7}$'),
    KycKind.rc: RegExp(r'^(?:[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{4}|[0-9]{2}BH[0-9]{4}[A-Z]{2})$'),
    KycKind.pan: RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$'),
    KycKind.gstin: RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
    KycKind.aadhaar: RegExp(r'^[0-9]{4}$'),
  };

  @override
  Future<KycResult> verify(KycKind kind, String number) async {
    final n = number.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (!_format[kind]!.hasMatch(n)) return const KycResult(KycStatus.notFound);
    if (kind == KycKind.aadhaar) return const KycResult(KycStatus.unavailable);
    final last = n[n.length - 1];
    if (last == '0') return const KycResult(KycStatus.notFound);
    if (last == '9' || last == 'Z') return const KycResult(KycStatus.mismatch, 'Sandbox Other Person');
    return const KycResult(KycStatus.verified, 'Sandbox Holder');
  }
}
