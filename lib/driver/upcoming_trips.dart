import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/scheduling/schedule.dart';
import '../core/services/booking_service.dart';
import '../core/services/pricing_service.dart';
import '../core/widgets/booking_widgets.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// The driver's advance bookings that are not due yet, soonest first.
List<Booking> upcomingTrips(Iterable<Booking> all, DateTime now, ScheduleRules rules) {
  final list = [for (final b in all) if (b.isUpcoming(now, rules)) b];
  list.sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
  return list;
}

/// "In 2 d 3 h" / "In 45 min" for a countdown line.
String countdownText(BuildContext context, DateTime target, DateTime now) {
  final u = Schedule.until(target, now);
  if (u.days > 0) return trf(context, 'startsInDays', {'d': u.days, 'h': u.hours});
  if (u.hours > 0) return trf(context, 'startsInHours', {'h': u.hours, 'm': u.minutes});
  return trf(context, 'startsInMinutes', {'m': u.minutes});
}

/// Full list of upcoming trips, with a countdown to each.
class UpcomingTripsScreen extends StatelessWidget {
  final ValueChanged<String> onOpen;

  /// Injectable for tests.
  final Stream<List<Booking>>? bookings;
  final DateTime Function() now;

  const UpcomingTripsScreen({super.key, required this.onOpen, this.bookings, this.now = DateTime.now});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: Text(tr(context, 'upcomingTrips'))),
      body: SafeArea(
        child: LiveStream<List<Booking>>(
          stream: () => bookings ?? BookingService.watchForDriver(),
          builder: (context, all) {
            final list = upcomingTrips(all, now(), PricingService.config.schedule);
            if (list.isEmpty) return EmptyState(icon: Icons.event_available_rounded, title: tr(context, 'noUpcomingTrips'));
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${formatDateTime(list[i].scheduledAt!)} · ${countdownText(context, list[i].scheduledAt!, now())}',
                    key: ValueKey('countdown_${list[i].id}'),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
                BookingCard(booking: list[i], onTap: () => onOpen(list[i].id)),
              ]),
            );
          },
        ),
      ),
    );
  }
}

/// Driver Home: the next two upcoming trips and a link to all of them.
class UpcomingTripsCard extends StatelessWidget {
  final ValueChanged<String> onOpen;
  final Stream<List<Booking>>? bookings;
  final DateTime Function() now;

  const UpcomingTripsCard({super.key, required this.onOpen, this.bookings, this.now = DateTime.now});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Booking>>(
      stream: bookings ?? BookingService.watchForDriver(),
      builder: (context, snap) {
        final list = upcomingTrips(snap.data ?? const [], now(), PricingService.config.schedule);
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: AppCard(
            key: const ValueKey('upcomingCard'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UpcomingTripsScreen(onOpen: onOpen, bookings: bookings, now: now))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.event_available_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(trf(context, 'upcomingCount', {'n': list.length}), style: const TextStyle(fontWeight: FontWeight.w800))),
                const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
              ]),
              for (final b in list.take(2))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${b.pickup} → ${b.drop} · ${countdownText(context, b.scheduledAt!, now())}', style: const TextStyle(color: AppColors.muted)),
                ),
            ]),
          ),
        );
      },
    );
  }
}
