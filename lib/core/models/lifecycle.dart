import '../constants/logistics.dart';
import 'booking.dart';
import 'load.dart';

/// The customer-facing lifecycle of a shipment (P12), derived from the load,
/// the booking and its payment record; nothing extra is stored.
enum LifecycleStage { created, matched, confirmed, pickedUp, inTransit, delivered, settled, cancelled }

const lifecycleOrder = [
  LifecycleStage.created,
  LifecycleStage.matched,
  LifecycleStage.confirmed,
  LifecycleStage.pickedUp,
  LifecycleStage.inTransit,
  LifecycleStage.delivered,
  LifecycleStage.settled,
];

/// [hasOfferSelected]: the customer picked a driver's offer that the driver
/// has not confirmed yet (so the load is "matched" but has no booking).
LifecycleStage lifecycleOf({Load? load, Booking? booking, bool hasOfferSelected = false}) {
  final b = booking;
  if (b != null) {
    if (b.status == BookingStatus.cancelled) return LifecycleStage.cancelled;
    if (b.status == BookingStatus.delivered) {
      return b.paymentStatus == 'driver_confirmed' ? LifecycleStage.settled : LifecycleStage.delivered;
    }
    if (b.status == BookingStatus.inTransit || b.status == BookingStatus.unloading) return LifecycleStage.inTransit;
    if (b.status == BookingStatus.pickedUp) return LifecycleStage.pickedUp;
    return LifecycleStage.confirmed;
  }
  if (load != null && load.cancelled) return LifecycleStage.cancelled;
  return hasOfferSelected ? LifecycleStage.matched : LifecycleStage.created;
}
