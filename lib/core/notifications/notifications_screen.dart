import 'package:flutter/material.dart';

import '../bilty/inspection_widgets.dart';
import '../models/app_notification.dart';
import '../models/user_settings.dart';
import '../services/server_clock.dart';
import '../services/settings_service.dart';
import '../services/notification_service.dart';
import '../widgets/common.dart';
import '../l10n/l10n.dart';
import '../widgets/live_stream.dart';
import '../widgets/logistics_labels.dart';
import '../reminders/reminders.dart';
import '../services/reminder_service.dart';
import '../widgets/reminder_widgets.dart';

/// Title for a notification in the current language.
String notificationTitle(
  BuildContext context,
  AppNotification n,
) => switch (n.type) {
  NotificationType.loadAccepted => tr(context, 'notifLoadAccepted'),
  NotificationType.statusChanged =>
    '${tr(context, 'notifStatusChanged')}: ${bookingStatusLabel(context, n.status ?? '')}',
  NotificationType.ratingReceived => tr(context, 'notifRatingReceived'),
  NotificationType.bookingCancelled => tr(context, 'notifBookingCancelled'),
  NotificationType.breakdownReported => tr(context, 'notifBreakdown'),
  NotificationType.arrivingSoon => tr(context, 'notifArrivingSoon'),
  NotificationType.chatMessage => tr(context, 'notifChat'),
  NotificationType.tripAssigned => tr(context, 'notifTripAssigned'),
  NotificationType.missedCall => tr(context, 'notifMissedCall'),
  NotificationType.lrSent => tr(context, 'notifLrSent'),
  NotificationType.inspectionRequest => tr(context, 'notifInspectionRequest'),
  NotificationType.inspectionApproved => tr(context, 'notifInspectionApproved'),
  NotificationType.inspectionDenied => tr(context, 'notifInspectionDenied'),
  _ => n.type,
};

IconData _iconFor(String type) => switch (type) {
  NotificationType.loadAccepted => Icons.handshake_outlined,
  NotificationType.statusChanged => Icons.local_shipping_outlined,
  NotificationType.ratingReceived => Icons.star_outline_rounded,
  NotificationType.bookingCancelled => Icons.cancel_outlined,
  NotificationType.breakdownReported => Icons.car_crash_outlined,
  NotificationType.arrivingSoon => Icons.near_me_rounded,
  NotificationType.chatMessage => Icons.chat_bubble_outline_rounded,
  NotificationType.tripAssigned => Icons.assignment_ind_outlined,
  NotificationType.missedCall => Icons.phone_missed_rounded,
  NotificationType.lrSent => Icons.receipt_long_outlined,
  NotificationType.inspectionRequest => Icons.policy_outlined,
  NotificationType.inspectionApproved => Icons.verified_user_outlined,
  NotificationType.inspectionDenied => Icons.block_outlined,
  _ => Icons.notifications_none_rounded,
};

/// Bell icon with an unread-count badge; opens [NotificationsScreen].
class NotificationBell extends StatefulWidget {
  /// Opens the booking a notification refers to.
  final ValueChanged<String> onOpenBooking;

  /// Which reminders the list shows (driver or customer rules).
  final bool isDriver;

  const NotificationBell({
    super.key,
    required this.onOpenBooking,
    this.isDriver = false,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final Stream<int> _unread = NotificationService.watchUnreadCount();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _unread,
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return IconButton(
          tooltip: tr(context, 'notifications'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NotificationsScreen(
                onOpenBooking: widget.onOpenBooking,
                isDriver: widget.isDriver,
              ),
            ),
          ),
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text(count > 99 ? '99+' : '$count'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
          color: AppColors.body,
        );
      },
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  final ValueChanged<String> onOpenBooking;
  final bool isDriver;

  /// Injectable for tests; defaults to the live [ReminderService].
  final Stream<List<Reminder>>? reminders;

  const NotificationsScreen({
    super.key,
    required this.onOpenBooking,
    this.isDriver = false,
    this.reminders,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

/// Which heading a notification sits under: 0 today, 1 yesterday, 2 earlier
/// (also for one without a time).
class NotifGroup {
  NotifGroup._();
  static const keys = ['notifToday', 'notifYesterday', 'notifEarlier'];

  static int of(DateTime? at, DateTime now) {
    if (at == null) return 2;
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    return days <= 0 ? 0 : (days == 1 ? 1 : 2);
  }
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _latest = const [];
  final ValueNotifier<bool> _hasUnread = ValueNotifier(true);

  /// Selected category chip (null = all).
  String? _category;

  late final Stream<List<AppNotification>> _stored = NotificationService.watchMine(applyPrefs: false).asBroadcastStream();
  // Not asBroadcastStream: that would keep the 1-minute timer alive after
  // the screen is closed.
  late final Stream<List<Reminder>> _reminders =
      widget.reminders ?? ReminderService.watch(isDriver: widget.isDriver);

  @override
  void dispose() {
    _hasUnread.dispose();
    super.dispose();
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      // Best effort: opening still works if marking read fails (e.g. offline).
      NotificationService.markRead(n.id).ignore();
    }
    if (n.type == NotificationType.inspectionRequest && n.relatedId.isNotEmpty) {
      await showInspectionDecision(context, n.relatedId);
      return;
    }
    if (n.relatedId.isNotEmpty) widget.onOpenBooking(n.relatedId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(
          tr(context, 'notifications'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            key: const ValueKey('notifSettings'),
            tooltip: tr(context, 'notifSettings'),
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openSettings,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _hasUnread,
            builder: (context, unread, _) => TextButton(
              key: const ValueKey('notifMarkAll'),
              // Nothing unread: nothing to mark.
              onPressed: unread ? () => NotificationService.markAllRead(_latest).ignore() : null,
              child: Text(tr(context, 'markAllRead')),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<NotificationPrefs>(
          valueListenable: SettingsService.prefs,
          builder: (context, prefs, _) => Column(
            children: [
              _chips(prefs),
              _remindersSection(prefs),
              Expanded(child: _notificationList(prefs)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chips(NotificationPrefs prefs) {
    return SizedBox(
      height: 52,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: const ValueKey('notifCat_all'),
              label: Text(tr(context, 'notifCatAll')),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
          ),
          for (final c in NotifCategory.all)
            if (prefs.isOn(c))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: ValueKey('notifCat_$c'),
                  label: Text(tr(context, 'notifCat_$c')),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
              ),
        ]),
      ),
    );
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _NotifSettingsSheet(),
    );
    // A muted category's chip disappears: fall back to All.
    if (mounted && _category != null && !SettingsService.prefs.value.isOn(_category!)) setState(() => _category = null);
  }

  /// Reminders worked out on this device (no push): shown above the stored
  /// notifications, not marked read.
  Widget _remindersSection(NotificationPrefs prefs) {
    return StreamBuilder<List<Reminder>>(
      stream: _reminders,
      builder: (context, snap) {
        final list = [
          for (final r in snap.data ?? const <Reminder>[])
            if (prefs.allowsReminder(r.kind) && (_category == null || NotifCategory.ofReminder(r.kind) == _category)) r,
        ];
        if (list.isEmpty) return const SizedBox.shrink();
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'remindersTitle'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                for (final r in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: KeyedSubtree(
                      key: ValueKey('notifReminder_${r.id}'),
                      child: ReminderTile(
                        reminder: r,
                        onTap: r.relatedId == null
                            ? null
                            : () => widget.onOpenBooking(r.relatedId!),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _notificationList(NotificationPrefs prefs) {
    return Builder(
      builder: (context) {
        return LiveStream<List<AppNotification>>(
          stream: () => _stored,
          builder: (context, all) {
            final items = [
              for (final n in all)
                if (prefs.allows(n.type) && (_category == null || NotifCategory.ofType(n.type) == _category)) n,
            ];
            _latest = items;
            final unread = items.any((n) => !n.read);
            if (_hasUnread.value != unread) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _hasUnread.value = unread;
              });
            }
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.notifications_none_rounded,
                title: tr(context, 'noNotifications'),
              );
            }
            // Today / Yesterday / Earlier headings between the cards (Task 29).
            final now = ServerClock.now();
            final rows = <Object>[];
            int? lastGroup;
            for (final n in items) {
              final g = NotifGroup.of(n.createdAt?.toDate(), now);
              if (g != lastGroup) rows.add(g);
              lastGroup = g;
              rows.add(n);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final row = rows[i];
                if (row is int) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(tr(context, NotifGroup.keys[row]), key: ValueKey('notifGroup_$row'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted)),
                  );
                }
                final n = row as AppNotification;
                return AppCard(
                  onTap: () => _open(n),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: n.read
                            ? AppColors.chip
                            : AppColors.primaryLight,
                        child: Icon(
                          _iconFor(n.type),
                          color: n.read ? AppColors.muted : AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notificationTitle(context, n),
                              style: TextStyle(
                                fontWeight: n.read
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                color: AppColors.title,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              n.message,
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                            if (n.createdAt != null)
                              Text(
                                formatDateTime(n.createdAt!.toDate()),
                                style: TextStyle(
                                  color: AppColors.faint,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!n.read)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: CircleAvatar(
                            radius: 5,
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// The five category switches. Safety alerts stay on.
class _NotifSettingsSheet extends StatefulWidget {
  const _NotifSettingsSheet();

  @override
  State<_NotifSettingsSheet> createState() => _NotifSettingsSheetState();
}

class _NotifSettingsSheetState extends State<_NotifSettingsSheet> {
  Future<void> _set(String category, bool on) async {
    final next = SettingsService.prefs.value.set(category, on);
    SettingsService.prefs.value = next; // takes effect at once
    try {
      await SettingsService.savePrefs(next);
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<NotificationPrefs>(
        valueListenable: SettingsService.prefs,
        builder: (context, prefs, _) => ListView(shrinkWrap: true, children: [
          for (final c in NotifCategory.all)
            SwitchListTile(
              key: ValueKey('notifSwitch_$c'),
              title: Text(tr(context, 'notifCat_$c')),
              value: prefs.isOn(c),
              onChanged: (v) => _set(c, v),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(tr(context, 'notifCriticalNote'), style: TextStyle(fontSize: 12, color: AppColors.faint)),
          ),
        ]),
      ),
    );
  }
}
