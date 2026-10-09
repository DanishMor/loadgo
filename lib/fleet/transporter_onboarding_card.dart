import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/onboarding/driver_onboarding.dart';
import '../core/onboarding/transporter_onboarding.dart';
import '../core/services/fleet_service.dart';
import '../core/services/transporter_service.dart';
import '../core/services/user_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import 'fleet_vehicles_screen.dart';
import 'transporter_profile_screen.dart';

/// Progress of a new transporter: profile, company details, a vehicle, a
/// driver, and the review by the team; with the reason after a rejection
/// (MASTER-6 Task 27). Hidden once everything is done.
class TransporterOnboardingCard extends StatefulWidget {
  /// Test hook; defaults to the live reads.
  final Future<TransporterOnboarding> Function()? load;
  const TransporterOnboardingCard({super.key, this.load});

  @override
  State<TransporterOnboardingCard> createState() => _TransporterOnboardingCardState();
}

class _TransporterOnboardingCardState extends State<TransporterOnboardingCard> {
  late Future<TransporterOnboarding> _data = (widget.load ?? _read)();

  static Future<TransporterOnboarding> _read() async {
    final user = await UserService.getUser();
    final own = await VehicleService.watchMine().first;
    final attached = await TransporterService.watchAttached().first;
    final members = await FleetService.watchMembers().first;
    return TransporterOnboarding.fromUser(user, vehicles: own.length + attached.length, members: members.where((m) => m.active).length);
  }

  void _refresh() {
    final next = (widget.load ?? _read)();
    setState(() {
      _data = next;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TransporterOnboarding>(
      future: _data,
      builder: (context, snap) {
        final o = snap.data;
        if (o == null || o.complete) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            key: const ValueKey('trOnboarding'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trf(context, 'obTitle', {'done': o.doneCount, 'total': o.steps.length}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              LinearProgressIndicator(key: const ValueKey('trObBar'), value: o.fraction, minHeight: 8, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 8),
              for (final s in o.steps)
                Row(children: [
                  Icon(s.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: s.done ? AppColors.success : AppColors.faint),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr(context, 'trObStep_${s.key}'), key: ValueKey('trObStep_${s.key}_${s.done ? 'done' : 'todo'}'))),
                ]),
              if (o.isRejected) ...[
                const SizedBox(height: 10),
                Text(tr(context, 'trObRejected'), key: const ValueKey('trObRejected'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.warning)),
                if (o.rejectReason.isNotEmpty) Text(tr(context, RejectReason.labelKey(o.rejectReason)), key: const ValueKey('trObReason')),
                if (o.rejectNote.isNotEmpty) Text(o.rejectNote, key: const ValueKey('trObNote'), style: TextStyle(color: AppColors.muted)),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                if (o.nextStep == 'profile' || o.nextStep == 'company' || o.isRejected)
                  FilledButton(key: const ValueKey('trObProfile'), onPressed: () => _open(const TransporterProfileScreen()), child: Text(tr(context, o.isRejected ? 'trObFix' : 'trObProfile'))),
                if (o.nextStep == 'vehicle') FilledButton(key: const ValueKey('trObVehicle'), onPressed: () => _open(const FleetVehiclesScreen()), child: Text(tr(context, 'trObAddVehicle'))),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
