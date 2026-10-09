import '../constants/logistics.dart';
import '../models/booking.dart';

/// Trust numbers for a driver, computed from their own booking records
/// (MASTER-6 Task 36). Display rules: percentages show only after
/// [minTrips] finished trips, so one late trip does not brand a new driver;
/// before that the card says "New".
class TrustBadges {
  final int finished; // delivered + cancelled by the driver
  final int delivered;
  final int onTimePercent; // of delivered trips with a known pickup time
  final int completionPercent; // delivered / (delivered + driver-cancelled)
  final int repeatCustomers; // customers booked more than once and delivered
  final int onTimeKnown;

  const TrustBadges({this.finished = 0, this.delivered = 0, this.onTimePercent = 0, this.completionPercent = 0, this.repeatCustomers = 0, this.onTimeKnown = 0});

  static const minTrips = 5;

  /// A pickup this long after the scheduled time still counts as on time.
  static const grace = Duration(minutes: 60);

  bool get isNew => finished < minTrips;
  bool get showOnTime => !isNew && onTimeKnown >= minTrips;
  bool get showCompletion => !isNew;
  bool get showRepeat => repeatCustomers > 0;

  /// On time: picked up by the end of the pickup date (a date-only pickup) or
  /// within [grace] of the scheduled time. Null when no pickup time is known.
  static bool? onTime(Booking b) {
    final at = b.timeline[BookingStatus.pickedUp];
    if (at == null) return null;
    final sched = b.scheduledAt;
    if (sched != null) return !at.isAfter(sched.add(grace));
    final d = b.pickupDate;
    if (d == null) return null;
    return at.isBefore(DateTime(d.year, d.month, d.day).add(const Duration(days: 1)));
  }

  /// [driverId] is the person the numbers are about: a trip counts for them
  /// when they hold it (or run it as the assigned driver).
  static TrustBadges compute(Iterable<Booking> bookings, String driverId) {
    var delivered = 0, cancelledByMe = 0, known = 0, ok = 0;
    final perCustomer = <String, int>{};
    for (final b in bookings) {
      if (b.driverId != driverId && b.assignedDriverId != driverId) continue;
      if (b.status == BookingStatus.delivered) {
        delivered++;
        perCustomer[b.customerId] = (perCustomer[b.customerId] ?? 0) + 1;
        final t = onTime(b);
        if (t != null) {
          known++;
          if (t) ok++;
        }
      } else if (b.status == BookingStatus.cancelled && b.cancellation?.by == 'driver') {
        cancelledByMe++;
      }
    }
    final finished = delivered + cancelledByMe;
    return TrustBadges(
      finished: finished,
      delivered: delivered,
      onTimeKnown: known,
      onTimePercent: known == 0 ? 0 : (ok * 100 / known).round(),
      completionPercent: finished == 0 ? 0 : (delivered * 100 / finished).round(),
      repeatCustomers: perCustomer.values.where((n) => n > 1).length,
    );
  }
}
