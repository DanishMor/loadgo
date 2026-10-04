import 'package:flutter/material.dart';

import '../models/app_notification.dart';
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
  _ => n.type,
};

IconData _iconFor(String type) => switch (type) {
  NotificationType.loadAccepted => Icons.handshake_outlined,
  NotificationType.statusChanged => Icons.local_shipping_outlined,
  NotificationType.ratingReceived => Icons.star_outline_rounded,
  NotificationType.bookingCancelled => Icons.cancel_outlined,
  NotificationType.breakdownReported => Icons.car_crash_outlined,
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

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _latest = const [];
  // Not asBroadcastStream: that would keep the 1-minute timer alive after
  // the screen is closed.
  late final Stream<List<Reminder>> _reminders =
      widget.reminders ?? ReminderService.watch(isDriver: widget.isDriver);

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      // Best effort: opening still works if marking read fails (e.g. offline).
      NotificationService.markRead(n.id).ignore();
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
          TextButton(
            onPressed: () => NotificationService.markAllRead(_latest).ignore(),
            child: Text(tr(context, 'markAllRead')),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _remindersSection(),
            Expanded(child: _notificationList()),
          ],
        ),
      ),
    );
  }

  /// Reminders worked out on this device (no push): shown above the stored
  /// notifications, not marked read.
  Widget _remindersSection() {
    return StreamBuilder<List<Reminder>>(
      stream: _reminders,
      builder: (context, snap) {
        final list = snap.data ?? const <Reminder>[];
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

  Widget _notificationList() {
    return Builder(
      builder: (context) {
        return LiveStream<List<AppNotification>>(
          stream: NotificationService.watchMine,
          builder: (context, items) {
            _latest = items;
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.notifications_none_rounded,
                title: tr(context, 'noNotifications'),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final n = items[i];
                return AppCard(
                  onTap: () => _open(n),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: n.read
                            ? const Color(0xFFF2F4F7)
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
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                            if (n.createdAt != null)
                              Text(
                                formatDateTime(n.createdAt!.toDate()),
                                style: const TextStyle(
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
