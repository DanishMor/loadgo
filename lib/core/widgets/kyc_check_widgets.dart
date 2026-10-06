import 'package:flutter/material.dart';

import '../identity/kyc_auto_check.dart';
import '../l10n/l10n.dart';
import '../services/admin_user_service.dart';
import '../services/user_service.dart';
import 'common.dart';

String kycProblemLabel(BuildContext context, String code) => tr(context, switch (code) {
      KycProblem.licenceExpired => 'kpLicenceExpired',
      KycProblem.licenceFormat => 'kpLicenceFormat',
      KycProblem.rcFormat => 'kpRcFormat',
      KycProblem.panFormat => 'kpPanFormat',
      KycProblem.aadhaarFormat => 'kpAadhaarFormat',
      KycProblem.nameMissing => 'kpNameMissing',
      KycProblem.editedAfterReview => 'kpEdited',
      _ => 'kpAdminFlag',
    });

String reviewKindLabel(BuildContext context, String kind) => tr(context, switch (kind) {
      ReviewKind.name => 'rkName',
      ReviewKind.rcOwner => 'rkRcOwner',
      ReviewKind.vehicle => 'rkVehicle',
      ReviewKind.document => 'rkDocument',
      _ => 'rkOther',
    });

/// Result of the automatic KYC check as chips (admin screens).
class AutoCheckChips extends StatelessWidget {
  final Map<String, dynamic> user;

  const AutoCheckChips({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final problems = kycAutoCheck(user);
    return Wrap(spacing: 6, runSpacing: 6, key: const ValueKey('autoCheck'), children: [
      if (problems.isEmpty) StatusChip(label: tr(context, 'autoCheckClean'), color: AppColors.success),
      for (final p in problems) StatusChip(label: kycProblemLabel(context, p), color: AppColors.warning),
    ]);
  }
}

/// Shown on the driver's Home when an admin marked a mismatch on the profile.
class ReviewFlagBanner extends StatefulWidget {
  final Stream<Map<String, dynamic>>? profile;

  const ReviewFlagBanner({super.key, this.profile});

  @override
  State<ReviewFlagBanner> createState() => _ReviewFlagBannerState();
}

class _ReviewFlagBannerState extends State<ReviewFlagBanner> {
  late final Stream<Map<String, dynamic>> _profile = widget.profile ?? UserService.watchUser().asBroadcastStream();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _profile,
      builder: (context, snap) {
        final f = snap.data?['reviewFlag'];
        if (f is! Map) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AppCard(
            key: const ValueKey('reviewFlagBanner'),
            child: Row(children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, 'reviewFlagTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${reviewKindLabel(context, f['kind'] as String? ?? ReviewKind.other)}: ${f['note'] ?? ''}', style: TextStyle(color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}
