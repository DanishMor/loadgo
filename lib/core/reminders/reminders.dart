import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/load.dart';
import '../models/offer.dart';
import '../models/vehicle.dart';

enum ReminderKind { pickupSoon, noDriverYet, vehicleDocs, serviceDue, tyreDue, licenceExpiring, offersWaiting, counterWaiting, confirmWaiting }

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

  const ReminderInput({
    required this.now,
    required this.isDriver,
    this.bookings = const [],
    this.loads = const [],
    this.offers = const [],
    this.vehicles = const [],
    this.licenceExpiry,
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

  static bool _inWindow(DateTime now, DateTime at) => !now.isBefore(at.subtract(leadTime)) && !now.isAfter(at.add(lateTime));

  /// Minutes until [at]; 0 once it has started.
  static int _minutes(DateTime now, DateTime at) {
    final m = at.difference(now).inMinutes;
    return m < 0 ? 0 : m;
  }
}
