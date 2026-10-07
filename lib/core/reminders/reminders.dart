import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/earnings.dart';
import '../models/load.dart';
import '../models/offer.dart';
import '../matching/return_loads.dart';
import '../models/vehicle.dart';
import '../trip/trip_eta.dart';

enum ReminderKind { tripDelayed, returnLoads, pickupSoon, noDriverYet, vehicleDocs, serviceDue, tyreDue, licenceExpiring, offersWaiting, counterWaiting, confirmWaiting, rateTrip }

/// An in-app reminder worked out from what the app already knows (no push,
/// nothing stored). LATER(paid): the same rules in a scheduled Cloud
/// Function + FCM, so they also arrive when the app is closed.
class Reminder {
  final ReminderKind kind;

  /// Stable per subject, so a screen can tell reminders apart.
  final String id;

  /// Placeholders for the translated text.
  final Map<String, Object> args;

  /// Booking or load the reminder is about, when there is one.
  final String? relatedId;

  /// Lower = more urgent.
  final int priority;

  const Reminder({required this.kind, required this.id, this.args = const {}, this.relatedId, required this.priority});
}

/// When a booking or load is due to be picked up: its date at the start of
/// the chosen slot.
DateTime pickupMoment(DateTime date, String slot) => DateTime(date.year, date.month, date.day, PickupSlot.startHour(slot));

/// Everything the reminder rules look at.
class ReminderInput {
  final DateTime now;
  final bool isDriver;
  final List<Booking> bookings;
  final List<Load> loads;
  final List<Offer> offers;
  final List<Vehicle> vehicles;

  /// Driver's licence expiry (from onboarding), if known.
  final DateTime? licenceExpiry;

  /// Estimated arrival of a booking (null = unknown); feeds the delay alert.
  final DateTime? Function(Booking)? etaOf;

  /// Bookings this user has already rated; null while unknown (no rating
  /// reminder is made until it is known).
  final Set<String>? ratedBookingIds;

  const ReminderInput({
    required this.now,
    required this.isDriver,
    this.bookings = const [],
    this.loads = const [],
    this.offers = const [],
    this.vehicles = const [],
    this.licenceExpiry,
    this.etaOf,
    this.ratedBookingIds,
  });
}

/// Pure rules: no I/O, no clock of its own.
class ReminderEngine {
  ReminderEngine._();

  /// A pickup reminder shows from this long before the slot starts ...
  static const leadTime = Duration(hours: 1);

  /// ... until this long after (the driver may be late).
  static const lateTime = Duration(hours: 2);

  static const expiryDays = 30;

  /// A delivered trip is "not rated yet" once this long has passed ...
  static const rateAfter = Duration(hours: 24);

  /// ... and the reminder stops after this many days.
  static const rateWindowDays = 14;

  static List<Reminder> compute(ReminderInput i) {
    final out = <Reminder>[];

    // Scheduled pickups, 1 hour ahead. Only trips that have not left yet.
    const notYetPickedUp = [BookingStatus.accepted, BookingStatus.driverArriving, BookingStatus.loading];
    for (final b in i.bookings) {
      final date = b.pickupDate;
      if (date == null || !notYetPickedUp.contains(b.status)) continue;
      final at = b.scheduledAt ?? pickupMoment(date, b.pickupSlot);
      if (_inWindow(i.now, at)) {
        out.add(Reminder(
          kind: ReminderKind.pickupSoon,
          id: 'pickup_${b.id}',
          args: {'route': '${b.pickup} → ${b.drop}', 'minutes': _minutes(i.now, at)},
          relatedId: b.id,
          priority: 0,
        ));
      }
    }

    // Both sides: a trip on the road well past its estimated arrival.
    if (i.etaOf != null) {
      for (final b in i.bookings) {
        final late = TripEta.delayMinutes(b, i.etaOf!(b), i.now);
        if (late != null) {
          out.add(Reminder(
            kind: ReminderKind.tripDelayed,
            id: 'delayed_${b.id}',
            args: {'route': '${b.pickup} → ${b.drop}', 'minutes': late},
            relatedId: b.id,
            priority: 0,
          ));
        }
      }
    }

    // Both sides: delivered a day ago or more and still not rated.
    final rated = i.ratedBookingIds;
    if (rated != null) {
      final waiting = [
        for (final b in i.bookings)
          if (b.status == BookingStatus.delivered && !rated.contains(b.id) && _rateDue(i.now, EarningsSummary.deliveredAt(b))) b,
      ]..sort((a, b) => EarningsSummary.deliveredAt(b).compareTo(EarningsSummary.deliveredAt(a)));
      if (waiting.isNotEmpty) {
        final latest = waiting.first;
        out.add(Reminder(
          kind: ReminderKind.rateTrip,
          id: 'rate_${latest.id}',
          args: {'n': waiting.length, 'route': '${latest.pickup} → ${latest.drop}'},
          relatedId: latest.id,
          priority: 3,
        ));
      }
    }

    if (!i.isDriver) {
      // Customer: a load with a pickup in the next hour and nobody on it.
      for (final l in i.loads) {
        final date = l.pickupDate;
        if (date == null || !l.isOpen) continue;
        final at = l.scheduledAt ?? pickupMoment(date, l.pickupSlot);
        if (_inWindow(i.now, at)) {
          out.add(Reminder(
            kind: ReminderKind.noDriverYet,
            id: 'nodriver_${l.id}',
            args: {'route': '${l.pickup} → ${l.drop}', 'minutes': _minutes(i.now, at)},
            relatedId: l.id,
            priority: 1,
          ));
        }
      }
      // Customer: drivers' prices waiting for an answer.
      final waiting = i.offers.where((o) => o.status == OfferStatus.pending).length;
      if (waiting > 0) {
        out.add(Reminder(kind: ReminderKind.offersWaiting, id: 'offers_waiting', args: {'n': waiting}, priority: 2));
      }
    } else {
      // Driver: a customer counter to answer, or a selection to confirm.
      final counters = i.offers.where((o) => o.status == OfferStatus.countered).length;
      if (counters > 0) {
        out.add(Reminder(kind: ReminderKind.counterWaiting, id: 'counter_waiting', args: {'n': counters}, priority: 2));
      }
      final confirms = i.offers.where((o) => o.status == OfferStatus.selected).length;
      if (confirms > 0) {
        out.add(Reminder(kind: ReminderKind.confirmWaiting, id: 'confirm_waiting', args: {'n': confirms}, priority: 1));
      }

      // Driver: loads for the way back from a trip that is about to end.
      for (final b in i.bookings) {
        if (b.status != BookingStatus.inTransit && b.status != BookingStatus.unloading) continue;
        final back = returnLoadsFor(b, i.loads);
        if (back.isNotEmpty) {
          out.add(Reminder(kind: ReminderKind.returnLoads, id: 'return_${b.id}', args: {'n': back.length, 'city': b.drop}, relatedId: b.id, priority: 2));
          break;
        }
      }

      // Driver: papers.
      final docs = i.vehicles.fold<int>(0, (n, v) => n + v.docsExpiringWithin(i.now, days: expiryDays).length);
      if (docs > 0) out.add(Reminder(kind: ReminderKind.vehicleDocs, id: 'vehicle_docs', args: {'n': docs}, priority: 3));
      final service = i.vehicles.where((v) => v.serviceDue(i.now)).length;
      if (service > 0) out.add(Reminder(kind: ReminderKind.serviceDue, id: 'service_due', args: {'n': service}, priority: 4));
      final tyres = i.vehicles.where((v) => v.tyreDue(i.now)).length;
      if (tyres > 0) out.add(Reminder(kind: ReminderKind.tyreDue, id: 'tyre_due', args: {'n': tyres}, priority: 4));
      final licence = i.licenceExpiry;
      if (licence != null) {
        final days = DateTime(licence.year, licence.month, licence.day).difference(DateTime(i.now.year, i.now.month, i.now.day)).inDays;
        if (days <= expiryDays) {
          out.add(Reminder(
            kind: ReminderKind.licenceExpiring,
            id: 'licence',
            args: {'days': days < 0 ? 0 : days, 'expired': days < 0 ? 1 : 0},
            priority: days < 0 ? 0 : 3,
          ));
        }
      }
    }

    out.sort((a, b) => a.priority.compareTo(b.priority));
    return out;
  }

  static bool _rateDue(DateTime now, DateTime deliveredAt) {
    if (deliveredAt.millisecondsSinceEpoch == 0) return false;
    final age = now.difference(deliveredAt);
    return age >= rateAfter && age <= const Duration(days: rateWindowDays);
  }

  static bool _inWindow(DateTime now, DateTime at) => !now.isBefore(at.subtract(leadTime)) && !now.isAfter(at.add(lateTime));

  /// Minutes until [at]; 0 once it has started.
  static int _minutes(DateTime now, DateTime at) {
    final m = at.difference(now).inMinutes;
    return m < 0 ? 0 : m;
  }
}
