import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/onboarding/driver_onboarding.dart';
import '../core/services/user_service.dart';
import '../core/widgets/common.dart';
import 'driver_kyc_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _user,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final o = DriverOnboarding.fromUser(snap.data);
        return AppCard(
          key: const ValueKey('onboardingCard'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trf(context, 'obTitle', {'done': o.doneCount, 'total': o.steps.length}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
                Expanded(child: Text(tr(context, 'obDoc_${d.key}'), style: TextStyle(color: AppColors.muted, fontSize: 13))),
              ]),
            if (o.isRejected) ...[
              const SizedBox(height: 12),
              Text(tr(context, 'obRejectedTitle'), key: const ValueKey('obRejected'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.warning)),
              if (o.rejectReason.isNotEmpty) Text(tr(context, RejectReason.labelKey(o.rejectReason)), key: const ValueKey('obReason')),
              if (o.rejectNote.isNotEmpty) Text(o.rejectNote, key: const ValueKey('obNote'), style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              FilledButton(key: const ValueKey('obResubmit'), onPressed: _resubmit, child: Text(tr(context, 'obResubmit'))),
            ],
          ]),
        );
      },
    );
  }
}
