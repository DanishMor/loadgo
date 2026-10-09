import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/backend.dart';
import '../widgets/common.dart';
import 'trust_badges.dart';

/// The driver's own trust numbers (MASTER-6 Task 36), from their own trips.
/// TODO(functions): showing them to customers on offers needs a server-written
/// summary; the app cannot read other people's trips, and a number the app
/// wrote about itself could be faked.
class TrustBadgesCard extends StatelessWidget {
  final Stream<List<Booking>> bookings;
  const TrustBadgesCard({super.key, required this.bookings});

  Widget _chip(BuildContext context, String id, IconData icon, String text) => Chip(key: ValueKey('badge_$id'), avatar: Icon(icon, size: 16, color: AppColors.success), label: Text(text));

  @override
  Widget build(BuildContext context) {
    final me = Backend.uid;
    if (me == null) return const SizedBox.shrink();
    return StreamBuilder<List<Booking>>(
      stream: bookings,
      builder: (context, snap) {
        final list = snap.data;
        if (snap.hasError || list == null) return const SizedBox.shrink();
        final t = TrustBadges.compute(list, me);
        if (list.isEmpty || t.finished == 0) return const SizedBox.shrink();
        return AppCard(
          key: const ValueKey('trustCard'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'tbHeading'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (t.isNew)
              Text(trf(context, 'tbNew', {'n': TrustBadges.minTrips - t.finished}), key: const ValueKey('badge_new'), style: TextStyle(color: AppColors.muted))
            else
              Wrap(spacing: 8, runSpacing: 4, children: [
                if (t.showOnTime) _chip(context, 'onTime', Icons.schedule_rounded, trf(context, 'tbOnTime', {'p': t.onTimePercent})),
                if (t.showCompletion) _chip(context, 'completion', Icons.task_alt_rounded, trf(context, 'tbCompletion', {'p': t.completionPercent})),
                if (t.showRepeat) _chip(context, 'repeat', Icons.repeat_rounded, trf(context, 'tbRepeat', {'n': t.repeatCustomers})),
              ]),
            const SizedBox(height: 4),
            Text(tr(context, 'tbNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ]),
        );
      },
    );
  }
}
