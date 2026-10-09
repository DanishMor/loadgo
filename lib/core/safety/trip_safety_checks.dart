import '../identity/kyc_validators.dart';
import '../models/booking.dart';
import '../services/safety_service.dart';

/// Pure rules for the driver's safety prompts (MASTER-6 Task 26).
class TripSafetyChecks {
  TripSafetyChecks._();

  /// Night driving hours (local time): 22:00 to 05:00.
  static bool isNight(DateTime t) => t.hour >= 22 || t.hour < 5;

  /// Statuses where the driver is on the road with the cargo.
  static const _driving = ['picked_up', 'in_transit'];

  /// The night prompt shows while the trip is on the road at night.
  static bool nightPrompt(String status, DateTime now) => _driving.contains(status) && isNight(now);

  /// A break is due this many hours after the trip started moving, or after the last break.
  static const restEveryHours = 4;

  /// When the clock for rest started: the later of the start of driving and the last break.
  static DateTime? restClockStart(Booking b, DateTime? lastBreak) {
    final started = b.timeline['in_transit'] ?? b.timeline['picked_up'];
    if (started == null) return null;
    if (lastBreak != null && lastBreak.isAfter(started)) return lastBreak;
    return started;
  }

  /// Hours of driving since the clock started, or null when the trip is not on the road.
  static int? hoursDriving(Booking b, DateTime now, DateTime? lastBreak) {
    if (!_driving.contains(b.status)) return null;
    final start = restClockStart(b, lastBreak);
    if (start == null) return null;
    final h = now.difference(start).inHours;
    return h < 0 ? 0 : h;
  }

  static bool restDue(Booking b, DateTime now, DateTime? lastBreak) {
    final h = hoursDriving(b, now, lastBreak);
    return h != null && h >= restEveryHours;
  }

  /// What is wrong with the emergency contacts: nothing, none saved, or some
  /// numbers are not valid Indian mobiles.
  static ContactsCheck contacts(List<EmergencyContact> list) {
    final bad = [for (final c in list) if (!isValidIndianMobile(c.phone)) c];
    return ContactsCheck(total: list.length, invalid: bad.length);
  }
}

class ContactsCheck {
  final int total;
  final int invalid;
  const ContactsCheck({required this.total, required this.invalid});

  bool get none => total == 0;
  bool get ok => total > 0 && invalid == 0;
  int get valid => total - invalid;
}
