import '../constants/logistics.dart';
import '../models/booking.dart';

/// Why a trip on the road is behind its estimate (MASTER-6 Task 18). Worked
/// out only from what the app already records, in this order, and always one
/// answer so the customer is not left guessing.
enum DelayReason { breakdown, vehicleChanged, loadingWait, unloadingWait, noSignal, nightRest, slowRoad }

class DelayWhy {
  final DelayReason reason;

  /// Minutes behind the reason (waiting minutes, silence minutes); 0 when it has none.
  final int minutes;
  const DelayWhy(this.reason, [this.minutes = 0]);
}

class DelayReasons {
  DelayReasons._();

  /// Waiting at a stop counts as a reason from this many minutes.
  static const longWaitMinutes = 60;

  /// No position for this long counts as a gap.
  static const silentMinutes = 45;

  /// Night hours (local): 22:00 to 05:00.
  static bool isNight(DateTime t) => t.hour >= 22 || t.hour < 5;

  /// The reason for a delay at [now]; null when the trip is not on the road.
  static DelayWhy? of(Booking b, DateTime now) {
    const onRoad = [BookingStatus.pickedUp, BookingStatus.inTransit, BookingStatus.unloading];
    if (!onRoad.contains(b.status)) return null;
    if (b.breakdown != null) return const DelayWhy(DelayReason.breakdown);
    if (b.replacedVehicleIds.isNotEmpty) return const DelayWhy(DelayReason.vehicleChanged);
    if (b.detention.loadingMinutes >= longWaitMinutes) return DelayWhy(DelayReason.loadingWait, b.detention.loadingMinutes);
    if (b.detention.unloadingMinutes >= longWaitMinutes) return DelayWhy(DelayReason.unloadingWait, b.detention.unloadingMinutes);
    final seen = b.locationUpdatedAt;
    if (seen != null && now.difference(seen).inMinutes >= silentMinutes) return DelayWhy(DelayReason.noSignal, now.difference(seen).inMinutes);
    if (isNight(now)) return const DelayWhy(DelayReason.nightRest);
    return const DelayWhy(DelayReason.slowRoad);
  }
}
