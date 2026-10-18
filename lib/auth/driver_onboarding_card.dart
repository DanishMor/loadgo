import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/onboarding/driver_onboarding.dart';
import '../core/services/user_service.dart';
import '../core/widgets/common.dart';
import 'driver_kyc_screen.dart';
import '../core/theme/design_tokens.dart';
import '../core/features/features.dart';
import '../core/services/features_service.dart';
import '../core/widgets/ds/app_button.dart';
import '../core/widgets/ds/status_badge.dart';

/// Progress bar, step list and document checklist of a driver in set-up, and
/// the reason plus a way to send documents again after a rejection
/// (MASTER-6 Task 21). Loads the user document itself unless [user] is given.
class DriverOnboardingCard extends StatefulWidget {
  final Map<String, dynamic>? user;

  /// Called after documents were sent again (the pending screen re-checks).
  final VoidCallback? onResubmitted;
  const DriverOnboardingCard({super.key, this.user, this.onResubmitted});

  @override
  State<DriverOnboardingCard> createState() => _DriverOnboardingCardState();
}

class _DriverOnboardingCardState extends State<DriverOnboardingCard> {
  late Future<Map<String, dynamic>?> _user = widget.user != null ? Future.value(widget.user) : UserService.getUser();

  Future<void> _resubmit() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const DriverKycScreen(edit: true)));
    if (ok == true && mounted) {
      setState(() { _user = UserService.getUser(); });
      widget.onResubmitted?.call();
    }
  }

  /// uiV2 (U34): the same facts, each with its state in words: a step is Done, the one to do Next, or Later; a
  /// document is Added or Missing; a rejection gets its own box with the reason and a big way to send again.
  Widget _v2(BuildContext context, DriverOnboarding o) {
    final c = context.ds;
    final next = o.nextStep;
    return AppCard(
      key: const ValueKey('onboardingCard'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(trf(context, 'obTitle', {'done': o.doneCount, 'total': o.steps.length}), style: DsType.title.copyWith(color: c.textStrong)),
        const SizedBox(height: DsSpace.s2),
        LinearProgressIndicator(key: const ValueKey('obBar'), value: o.fraction, minHeight: 10, borderRadius: DsRadius.all(DsRadius.pill)),
        const SizedBox(height: DsSpace.s3),
        for (final s in o.steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
            child: Row(children: [
              Icon(s.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 22, color: s.done ? c.success : c.textMuted),
              const SizedBox(width: DsSpace.s2),
              Expanded(child: Text(tr(context, 'obStep_${s.key}'), key: ValueKey('obStep_${s.key}_${s.done ? 'done' : 'todo'}'), style: DsType.body.copyWith(color: c.text))),
              const SizedBox(width: DsSpace.s2),
              StatusBadge(
                key: ValueKey('obState_${s.key}'),
                label: tr(context, s.done ? 'obStateDone' : (s.key == next ? 'obStateNext' : 'obStateLater')),
                tone: s.done ? StatusTone.success : (s.key == next ? StatusTone.attention : StatusTone.neutral),
                showIcon: false,
              ),
            ]),
          ),
        const SizedBox(height: DsSpace.s3),
        for (final d in o.docs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
            child: Row(children: [
              Expanded(child: Text(tr(context, 'obDoc_${d.key}'), style: DsType.bodySmall.copyWith(color: c.textMuted))),
              const SizedBox(width: DsSpace.s2),
              StatusBadge(label: tr(context, d.present ? 'obDocAdded' : 'obDocMissing'), tone: d.present ? StatusTone.success : StatusTone.attention),
            ]),
          ),
        if (o.isRejected) ...[
          const SizedBox(height: DsSpace.s3),
          Container(
            padding: const EdgeInsets.all(DsSpace.s3),
            decoration: BoxDecoration(color: c.errorBg, borderRadius: DsRadius.all(DsRadius.md)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'obRejectedTitle'), key: const ValueKey('obRejected'), style: DsType.label.copyWith(color: c.error)),
              const SizedBox(height: DsSpace.s1),
              Text(tr(context, 'obWhyRejected'), style: DsType.caption.copyWith(color: c.textMuted)),
              if (o.rejectReason.isNotEmpty) Text(tr(context, RejectReason.labelKey(o.rejectReason)), key: const ValueKey('obReason'), style: DsType.body.copyWith(color: c.textStrong)),
              if (o.rejectNote.isNotEmpty) Text(o.rejectNote, key: const ValueKey('obNote'), style: DsType.body.copyWith(color: c.textMuted)),
              const SizedBox(height: DsSpace.s3),
              AppButton(key: const ValueKey('obResubmit'), label: tr(context, 'obResubmit'), big: true, onPressed: _resubmit),
            ]),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _user,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final o = DriverOnboarding.fromUser(snap.data);
        if (FeaturesService.isOn(FeatureKey.uiV2)) return _v2(context, o);
        return AppCard(
          key: const ValueKey('onboardingCard'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trf(context, 'obTitle', {'done': o.doneCount, 'total': o.steps.length}), style: DsStyle.t16w700),
            const SizedBox(height: 8),
            LinearProgressIndicator(key: const ValueKey('obBar'), value: o.fraction, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 8),
            for (final s in o.steps)
              Row(children: [
                Icon(s.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: s.done ? AppColors.success : AppColors.faint),
                const SizedBox(width: 8),
                Expanded(child: Text(tr(context, 'obStep_${s.key}'), key: ValueKey('obStep_${s.key}_${s.done ? 'done' : 'todo'}'))),
              ]),
            const SizedBox(height: 10),
            for (final d in o.docs)
              Row(children: [
                Icon(d.present ? Icons.check_rounded : Icons.close_rounded, size: 16, color: d.present ? AppColors.success : AppColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text(tr(context, 'obDoc_${d.key}'), style: DsStyle.t14w400.copyWith(color: AppColors.muted))),
              ]),
            if (o.isRejected) ...[
              const SizedBox(height: 12),
              Text(tr(context, 'obRejectedTitle'), key: const ValueKey('obRejected'), style: DsStyle.w700.copyWith(color: AppColors.warning)),
              if (o.rejectReason.isNotEmpty) Text(tr(context, RejectReason.labelKey(o.rejectReason)), key: const ValueKey('obReason')),
              if (o.rejectNote.isNotEmpty) Text(o.rejectNote, key: const ValueKey('obNote'), style: DsStyle.inherit.copyWith(color: AppColors.muted)),
              const SizedBox(height: 8),
              FilledButton(key: const ValueKey('obResubmit'), onPressed: _resubmit, child: Text(tr(context, 'obResubmit'))),
            ],
          ]),
        );
      },
    );
  }
}
