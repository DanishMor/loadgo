import 'package:flutter/material.dart';

import '../../core/models/app_notification.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import '../../core/widgets/live_stream.dart';
import '../../core/widgets/logistics_labels.dart';

/// Title for a notification in the current language.
String notificationTitle(BuildContext context, AppNotification n) => switch (n.type) {
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

  const NotificationBell({super.key, required this.onOpenBooking});

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
            MaterialPageRoute(builder: (_) => NotificationsScreen(onOpenBooking: widget.onOpenBooking)),
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

  const NotificationsScreen({super.key, required this.onOpenBooking});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _latest = const [];

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
        title: Text(tr(context, 'notifications'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: () => NotificationService.markAllRead(_latest).ignore(),
            child: Text(tr(context, 'markAllRead')),
          ),
        ],
      ),
      body: SafeArea(
        child: LiveStream<List<AppNotification>>(
          stream: NotificationService.watchMine,
          builder: (context, items) {
            _latest = items;
            if (items.isEmpty) {
              return EmptyState(icon: Icons.notifications_none_rounded, title: tr(context, 'noNotifications'));
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
                        backgroundColor: n.read ? const Color(0xFFF2F4F7) : AppColors.primaryLight,
                        child: Icon(_iconFor(n.type), color: n.read ? AppColors.muted : AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notificationTitle(context, n),
                              style: TextStyle(
                                fontWeight: n.read ? FontWeight.w600 : FontWeight.w800,
                                color: AppColors.title,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(n.message, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                            if (n.createdAt != null)
                              Text(formatDateTime(n.createdAt!.toDate()),
                                  style: const TextStyle(color: AppColors.faint, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (!n.read)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: CircleAvatar(radius: 5, backgroundColor: AppColors.primary),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
