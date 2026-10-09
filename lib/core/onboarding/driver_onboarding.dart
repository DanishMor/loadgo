/// Where a driver is on the way to taking loads (MASTER-6 Task 21), worked
/// out from the user document only: no extra reads.
class OnboardingStep {
  final String key; // profile, consent, documents, review
  final bool done;
  const OnboardingStep(this.key, this.done);
}

/// One line of the document checklist.
class DocLine {
  final String key; // licence, licenceExpiry, rc, aadhaar, pan
  final bool present;
  const DocLine(this.key, this.present);
}

/// Why a verifier did not approve (stored in `verificationMeta.reason`).
class RejectReason {
  RejectReason._();
  static const docsUnclear = 'docs_unclear';
  static const nameMismatch = 'name_mismatch';
  static const licenceExpired = 'licence_expired';
  static const rcMismatch = 'rc_mismatch';
  static const other = 'other';
  static const all = [docsUnclear, nameMismatch, licenceExpired, rcMismatch, other];

  static const maxNote = 120;

  static String labelKey(String code) => 'rej_$code';
}

class DriverOnboarding {
  final List<OnboardingStep> steps;
  final List<DocLine> docs;

  /// `pending`, `approved` or `rejected` (a missing status counts as pending).
  final String status;
  final String rejectReason;
  final String rejectNote;

  const DriverOnboarding({required this.steps, required this.docs, required this.status, this.rejectReason = '', this.rejectNote = ''});

  int get doneCount => steps.where((s) => s.done).length;

  /// 0..1 for the progress bar.
  double get fraction => steps.isEmpty ? 0 : doneCount / steps.length;

  bool get isRejected => status == 'rejected';

  /// The first step not done, or null when all are.
  String? get nextStep {
    for (final s in steps) {
      if (!s.done) return s.key;
    }
    return null;
  }

  bool get documentsComplete => docs.every((d) => d.present);

  static DriverOnboarding fromUser(Map<String, dynamic>? u) {
    final user = u ?? const <String, dynamic>{};
    final kyc = user['driverKyc'] is Map ? user['driverKyc'] as Map : const {};
    bool has(String k) => '${kyc[k] ?? ''}'.trim().isNotEmpty;
    final status = user['verificationStatus'] == 'rejected'
        ? 'rejected'
        : (user['verified'] == true || user['verificationStatus'] == 'approved') ? 'approved' : 'pending';
    final meta = user['verificationMeta'] is Map ? user['verificationMeta'] as Map : const {};
    return DriverOnboarding(
      steps: [
        OnboardingStep('profile', user['driverProfileComplete'] == true),
        OnboardingStep('consent', user['locationConsentAsked'] == true),
        OnboardingStep('documents', user['kycComplete'] == true),
        OnboardingStep('review', status == 'approved'),
      ],
      docs: [
        DocLine('licence', has('dlNumber')),
        DocLine('licenceExpiry', kyc['dlExpiry'] != null),
        DocLine('rc', has('rcNumber')),
        DocLine('aadhaar', has('aadhaarLast4')),
        DocLine('pan', has('pan')),
      ],
      status: status,
      rejectReason: status == 'rejected' && RejectReason.all.contains(meta['reason']) ? meta['reason'] as String : '',
      rejectNote: status == 'rejected' ? '${meta['note'] ?? ''}' : '',
    );
  }
}
