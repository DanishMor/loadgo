import 'package:flutter/material.dart';

import '../core/constants/logistics.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/load.dart';
import '../core/models/support_ticket.dart';
import '../core/support/support_screens.dart';
import '../core/widgets/common.dart';
import 'post_load_screen.dart';

/// A new Post Load form filled from a delivered trip: same places, goods,
/// vehicle and notes, no date (MASTER-6 Task 20).
Load loadDraftFromBooking(Booking b) => Load(
      id: '',
      shipperId: '',
      pickup: b.pickup,
      drop: b.drop,
      cargoType: b.cargoType,
      weight: b.weight,
      vehicleType: b.vehicleType,
      budget: b.budget,
      pickupDate: null,
      notes: b.notes,
      status: LoadStatus.open,
      extraPickups: b.extraPickups,
      extraDrops: b.extraDrops,
    );

void bookAgain(BuildContext context, Booking b) =>
    Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => PostLoadScreen(repostFrom: loadDraftFromBooking(b))));

void reportIssue(BuildContext context, Booking b) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NewTicketScreen(bookingId: b.id, category: TicketCategory.bookingIssue)));

/// Under the rating after delivery: report a problem with this trip, or book
/// the same trip again in one tap.
class DeliveredActionsCard extends StatelessWidget {
  final Booking booking;
  const DeliveredActionsCard({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const ValueKey('deliveredActions'),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(key: const ValueKey('bookAgain'), onPressed: () => bookAgain(context, booking), icon: const Icon(Icons.replay_rounded), label: Text(tr(context, 'bookAgain'))),
        OutlinedButton.icon(key: const ValueKey('reportIssue'), onPressed: () => reportIssue(context, booking), icon: const Icon(Icons.report_problem_outlined), label: Text(tr(context, 'reportIssue'))),
      ]),
    );
  }
}

/// Wraps the delivered block. When the status turns to delivered while the
/// customer is looking at the screen, a sheet offers Rate, Report an issue and
/// Book again once; opening an already delivered trip shows no sheet.
class DeliveredWatcher extends StatefulWidget {
  final Booking booking;
  final Widget child;
  const DeliveredWatcher({super.key, required this.booking, required this.child});

  /// Whether a status change from [before] to [after] is a fresh delivery.
  static bool justDelivered(String? before, String after) => before != null && before != BookingStatus.delivered && after == BookingStatus.delivered;

  @override
  State<DeliveredWatcher> createState() => _DeliveredWatcherState();
}

class _DeliveredWatcherState extends State<DeliveredWatcher> {
  @override
  void didUpdateWidget(DeliveredWatcher old) {
    super.didUpdateWidget(old);
    if (DeliveredWatcher.justDelivered(old.booking.status, widget.booking.status)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sheet();
      });
    }
  }

  Future<void> _sheet() async {
    final b = widget.booking;
    final host = context;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(c, 'deliveredTitle'), key: const ValueKey('deliveredSheet'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr(c, 'deliveredBody'), style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('deliveredRate'),
              onPressed: () {
                Navigator.pop(c);
                if (host.mounted) Scrollable.ensureVisible(host, duration: const Duration(milliseconds: 300));
              },
              icon: const Icon(Icons.star_rounded),
              label: Text(tr(c, 'rateNow')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(key: const ValueKey('deliveredBookAgain'), onPressed: () { Navigator.pop(c); bookAgain(host, b); }, icon: const Icon(Icons.replay_rounded), label: Text(tr(c, 'bookAgain'))),
            const SizedBox(height: 8),
            TextButton.icon(key: const ValueKey('deliveredIssue'), onPressed: () { Navigator.pop(c); reportIssue(host, b); }, icon: const Icon(Icons.report_problem_outlined), label: Text(tr(c, 'reportIssue'))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
