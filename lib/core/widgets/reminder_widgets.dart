import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../reminders/reminders.dart';
import '../services/reminder_service.dart';
import 'common.dart';

/// Translated sentence for a reminder.
String reminderText(BuildContext context, Reminder r) => switch (r.kind) {
      ReminderKind.pickupSoon => trf(context, 'remPickupSoon', r.args),
      ReminderKind.noDriverYet => trf(context, 'remNoDriver', r.args),
      ReminderKind.vehicleDocs => trf(context, 'remVehicleDocs', r.args),
      ReminderKind.serviceDue => trf(context, 'remServiceDue', r.args),
      ReminderKind.licenceExpiring =>
        r.args['expired'] == 1 ? tr(context, 'remLicenceExpired') : trf(context, 'remLicenceSoon', r.args),
      ReminderKind.offersWaiting => trf(context, 'remOffersWaiting', r.args),
      ReminderKind.counterWaiting => trf(context, 'remCounterWaiting', r.args),
      ReminderKind.confirmWaiting => trf(context, 'remConfirmWaiting', r.args),
    };

IconData reminderIcon(ReminderKind k) => switch (k) {
      ReminderKind.pickupSoon || ReminderKind.noDriverYet => Icons.schedule_rounded,
      ReminderKind.vehicleDocs || ReminderKind.licenceExpiring => Icons.assignment_late_rounded,
      ReminderKind.serviceDue => Icons.build_circle_outlined,
      ReminderKind.offersWaiting || ReminderKind.counterWaiting || ReminderKind.confirmWaiting => Icons.local_offer_outlined,
    };

/// One reminder as a card row.
class ReminderTile extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback? onTap;
  const ReminderTile({super.key, required this.reminder, this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Icon(reminderIcon(reminder.kind), color: AppColors.warning),
        const SizedBox(width: 12),
        Expanded(child: Text(reminderText(context, reminder), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.title))),
        if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
      ]),
    );
  }
}

/// Home banner: the most urgent reminders (up to [max]); hidden when there
/// is nothing to remind about. [onOpen] gets the reminder that was tapped.
class RemindersBanner extends StatefulWidget {
  final bool isDriver;
  final ValueChanged<Reminder> onOpen;
  final int max;

  /// Injectable for tests.
  final Stream<List<Reminder>>? source;

  const RemindersBanner({super.key, required this.isDriver, required this.onOpen, this.max = 3, this.source});

  @override
  State<RemindersBanner> createState() => _RemindersBannerState();
}

class _RemindersBannerState extends State<RemindersBanner> {
  late final Stream<List<Reminder>> _stream = widget.source ?? ReminderService.watch(isDriver: widget.isDriver);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Reminder>>(
      stream: _stream,
      builder: (context, snap) {
        final list = snap.data ?? const <Reminder>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(children: [
            for (final r in list.take(widget.max))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: KeyedSubtree(key: ValueKey('reminder_${r.id}'), child: ReminderTile(reminder: r, onTap: () => widget.onOpen(r))),
              ),
            if (list.length > widget.max)
              Text(trf(context, 'remMore', {'n': list.length - widget.max}), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        );
      },
    );
  }
}
