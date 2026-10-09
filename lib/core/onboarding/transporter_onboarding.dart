import 'driver_onboarding.dart';

/// Where a transporter is on the way to a first booking (MASTER-6 Task 27),
/// from the user document and two counts.
class TransporterOnboarding {
  final List<OnboardingStep> steps;
  final String status;
  final String rejectReason;
  final String rejectNote;

  const TransporterOnboarding({required this.steps, required this.status, this.rejectReason = '', this.rejectNote = ''});

  int get doneCount => steps.where((s) => s.done).length;
  double get fraction => steps.isEmpty ? 0 : doneCount / steps.length;
  bool get isRejected => status == 'rejected';
  bool get complete => steps.every((s) => s.done);

  String? get nextStep {
    for (final s in steps) {
      if (!s.done) return s.key;
    }
    return null;
  }

  /// [vehicles] counts the transporter's own and attached vehicles; [members]
  /// the active drivers in the fleet.
  static TransporterOnboarding fromUser(Map<String, dynamic>? u, {required int vehicles, required int members}) {
    final user = u ?? const <String, dynamic>{};
    final fleet = user['fleet'] is Map ? user['fleet'] as Map : const {};
    final business = user['business'] is Map ? user['business'] as Map : const {};
    final status = user['verificationStatus'] == 'rejected'
        ? 'rejected'
        : (user['verified'] == true || user['verificationStatus'] == 'approved') ? 'approved' : 'pending';
    final meta = user['verificationMeta'] is Map ? user['verificationMeta'] as Map : const {};
    final company = '${business['gstin'] ?? ''}'.isNotEmpty || ('${fleet['officeCity'] ?? ''}'.isNotEmpty && (fleet['routes'] is List && (fleet['routes'] as List).isNotEmpty));
    return TransporterOnboarding(
      steps: [
        OnboardingStep('profile', user['fleetProfileComplete'] == true),
        OnboardingStep('company', company),
        OnboardingStep('vehicle', vehicles > 0),
        OnboardingStep('driver', members > 0),
        OnboardingStep('review', status == 'approved'),
      ],
      status: status,
      rejectReason: status == 'rejected' && RejectReason.all.contains(meta['reason']) ? meta['reason'] as String : '',
      rejectNote: status == 'rejected' ? '${meta['note'] ?? ''}' : '',
    );
  }
}
