import '../../core/models/booking.dart';
import '../../core/models/load.dart';
import '../../core/scheduling/schedule.dart';
import '../../core/dispatch/dispatch_models.dart';
import 'booking_wizard_model.dart';

enum TripSegment { active, upcoming, past }

/// One row of the Trips tab: a booking (a driver is on it) or a load still looking for a driver.
class TripItem {
  final Booking? booking;
  final Load? load;
  const TripItem.booking(Booking this.booking) : load = null;
  const TripItem.load(Load this.load) : booking = null;

  String get id => booking?.id ?? load!.id;
  String get pickup => booking?.pickup ?? load!.pickup;
  String get drop => booking?.drop ?? load!.drop;
  String get cargo => booking?.cargoType ?? load!.cargoType;
  num get weight => booking?.weight ?? load!.weight;
  String get vehicleType => booking?.vehicleType ?? load!.vehicleType;
  bool get isWaitingLoad => load != null;

  /// The time the list is sorted by: the pickup moment for something upcoming, else when it was made.
  DateTime? get when => booking != null ? (booking!.scheduledAt ?? booking!.createdAt?.toDate()) : (load!.scheduledAt ?? load!.createdAt?.toDate());

  /// What to start a repeat booking from: the same route, goods and truck, at the price step.
  WizardDraft toDraft() => WizardDraft(
        pickup: pickup,
        drop: drop,
        cargo: WizardDraft.fromJson({'cargo': cargo}).cargo,
        weightTons: weight > 0 && weight <= WizardDraft.maxWeight ? weight.toDouble() : null,
        vehicleType: vehicleType.isEmpty ? null : vehicleType,
        step: 3,
      );
}

/// Sorts bookings and loads into the three tabs (U23). Pure.
class TripBuckets {
  final List<TripItem> active, upcoming, past;
  const TripBuckets(this.active, this.upcoming, this.past);

  static int _newestFirst(TripItem a, TripItem b) {
    final x = a.when, y = b.when;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  }

  static int _soonestFirst(TripItem a, TripItem b) {
    final x = a.when, y = b.when;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }

  static TripBuckets compute({required List<Booking> bookings, required List<Load> loads, required DateTime now, required ScheduleRules rules}) {
    final active = <TripItem>[], upcoming = <TripItem>[], past = <TripItem>[];
    for (final b in bookings) {
      if (b.isActive && b.isUpcoming(now, rules)) {
        upcoming.add(TripItem.booking(b));
      } else if (b.isActive) {
        active.add(TripItem.booking(b));
      } else {
        past.add(TripItem.booking(b));
      }
    }
    for (final l in loads) {
      if (l.isOpen) {
        (l.mode == LoadMode.scheduled ? upcoming : active).add(TripItem.load(l));
      } else if (l.bookingId == null) {
        past.add(TripItem.load(l)); // closed with no driver: expired or cancelled, can be booked again
      }
      // a load that has a booking is shown through its booking
    }
    active.sort(_newestFirst);
    upcoming.sort(_soonestFirst);
    past.sort(_newestFirst);
    return TripBuckets(active, upcoming, past);
  }

  List<TripItem> of(TripSegment s) => switch (s) {
        TripSegment.active => active,
        TripSegment.upcoming => upcoming,
        TripSegment.past => past,
      };
}
