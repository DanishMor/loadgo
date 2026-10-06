import 'package:flutter/material.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/pricing_service.dart';
import '../trip/arrival_eta.dart';
import '../trip/trip_eta.dart';
import 'common.dart';

/// "35 min", "2 h 10 min" or "1 d 4 h".
String durationText(BuildContext context, Duration d) {
  final mins = d.inMinutes < 1 ? 1 : d.inMinutes;
  if (mins < 60) return trf(context, 'durMin', {'n': mins});
  if (mins < 60 * 48) return trf(context, 'durHourMin', {'h': mins ~/ 60, 'm': mins % 60});
  return trf(context, 'durDayHour', {'d': mins ~/ (60 * 24), 'h': (mins % (60 * 24)) ~/ 60});
}

/// Road km along the booking's stops from the offline city table, or null.
int? bookingRouteKm(Booking b) => PricingService.estimateRouteKm([b.pickup, ...b.extraPickups, ...b.extraDrops, b.drop]);

/// Estimated arrival (on the road), estimated trip time (before pickup),
/// a late warning, or the time the finished trip took. Hidden when the places
/// are not in the offline table.
class TripEtaCard extends StatelessWidget {
  final Booking booking;
  final DateTime Function()? clock;

  const TripEtaCard({super.key, required this.booking, this.clock});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    if (b.status == BookingStatus.cancelled) return const SizedBox.shrink();
    final now = (clock ?? DateTime.now)();
    final km = bookingRouteKm(b);
    final took = TripEta.roadTime(b);
    final String line;
    var late = false;
    if (took != null) {
      line = trf(context, 'etaTookTotal', {'time': durationText(context, took)});
    } else {
      final eta = TripEta.eta(b, km);
      if (eta != null) {
        final delay = TripEta.delayMinutes(b, eta, now);
        late = delay != null;
        line = late
            ? trf(context, 'etaDelayed', {'time': durationText(context, Duration(minutes: delay))})
            : '${tr(context, 'etaTitle')}: ${formatDateTime(eta)}';
      } else if (km != null && b.timeline[BookingStatus.pickedUp] == null) {
        line = trf(context, 'etaTripTime', {'time': durationText(context, TripEta.travelTime(km))});
      } else {
        return const SizedBox.shrink();
      }
    }
    return AppCard(
      key: const ValueKey('tripEtaCard'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(late ? Icons.warning_amber_rounded : Icons.schedule_rounded, color: late ? AppColors.warning : AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(line, key: const ValueKey('tripEtaLine'), style: TextStyle(fontWeight: FontWeight.w800, color: late ? AppColors.warning : AppColors.title))),
        ]),
        if (took == null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr(context, 'etaNote'), style: TextStyle(fontSize: 12, color: AppColors.faint))),
      ]),
    );
  }
}

/// Before pickup: how far the driver still is, from the position the driver
/// app shares on the way to the pickup. Hidden without a shared position.
class ArrivalEtaCard extends StatelessWidget {
  final Booking booking;
  final DateTime Function()? clock;

  const ArrivalEtaCard({super.key, required this.booking, this.clock});

  @override
  Widget build(BuildContext context) {
    final eta = ArrivalEta.of(booking, now: (clock ?? DateTime.now)());
    if (eta == null) return const SizedBox.shrink();
    return AppCard(
      key: const ValueKey('arrivalEtaCard'),
      child: Row(children: [
        Icon(eta.arrived ? Icons.where_to_vote_rounded : Icons.directions_car_rounded, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            eta.arrived ? tr(context, 'arrivalAtPickup') : trf(context, 'arrivalEtaLine', {'km': eta.km, 'time': durationText(context, eta.time)}),
            key: const ValueKey('arrivalEtaLine'),
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title),
          ),
        ),
      ]),
    );
  }
}
