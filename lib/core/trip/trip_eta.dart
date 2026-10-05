import '../constants/logistics.dart';
import '../models/booking.dart';

/// One reached step of the trip and how long it took after the previous one.
class StepTime {
  final String status;
  final DateTime at;
  final Duration? sincePrevious;

  const StepTime(this.status, this.at, this.sincePrevious);
}

/// ETA, step durations and delay rules for a trip (pure). The estimate is the
/// offline road distance at an average speed that already includes stops, not
/// live traffic. LATER(paid): routing / traffic API.
class TripEta {
  TripEta._();

  /// Average km per hour on the road, rests and queues included.
  static const speedKmph = 40.0;

  /// A trip is "late" only after this many minutes past the estimate.
  static const graceMinutes = 60;

  /// Time on the road for [km].
  static Duration travelTime(int km) => Duration(minutes: (km / speedKmph * 60).round());

  /// When the trip should arrive: the pickup (picked_up) time plus the travel
  /// time. Null before pickup or when the distance is unknown.
  static DateTime? eta(Booking b, int? km) {
    final left = b.timeline[BookingStatus.pickedUp] ?? b.timeline[BookingStatus.inTransit];
    if (left == null || km == null) return null;
    return left.add(travelTime(km));
  }

  static const _onTheRoad = [BookingStatus.pickedUp, BookingStatus.inTransit, BookingStatus.unloading];

  /// Minutes past the estimate (beyond the grace period) for a trip still on
  /// the road; null when on time, not on the road, or no estimate.
  static int? delayMinutes(Booking b, DateTime? eta, DateTime now) {
    if (eta == null || !_onTheRoad.contains(b.status)) return null;
    final late = now.difference(eta).inMinutes;
    return late > graceMinutes ? late : null;
  }

  /// The reached steps in order, each with the time since the one before.
  static List<StepTime> steps(Booking b) {
    final out = <StepTime>[];
    DateTime? prev;
    for (final s in BookingStatus.flow) {
      final t = b.timeline[s];
      if (t == null) continue;
      out.add(StepTime(s, t, prev == null ? null : t.difference(prev)));
      prev = t;
    }
    return out;
  }

  /// Time on the road: pickup to delivery. Null until delivered.
  static Duration? roadTime(Booking b) {
    final from = b.timeline[BookingStatus.pickedUp];
    final to = b.timeline[BookingStatus.delivered];
    return from == null || to == null ? null : to.difference(from);
  }
}
