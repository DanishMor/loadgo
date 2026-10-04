import '../constants/logistics.dart';

/// Why a chosen pickup time is not allowed.
enum ScheduleProblem { tooSoon, tooFar }

/// Advance-booking rules, all from `config/pricing` (see [ScheduleRules]).
class ScheduleRules {
  /// A scheduled pickup must be at least this many minutes away.
  final int minMinutes;

  /// ... and at most this many days away.
  final int maxDays;

  /// A scheduled booking turns "active" this many minutes before its time.
  final int leadMinutes;

  /// Cancelling is free until this many hours before the pickup time.
  final int freeCancelHours;

  const ScheduleRules({this.minMinutes = 60, this.maxDays = 30, this.leadMinutes = 60, this.freeCancelHours = 2});

  factory ScheduleRules.fromMap(Map<String, dynamic>? m, {int freeCancelHours = 2}) => ScheduleRules(
        minMinutes: (m?['minMinutes'] as num?)?.round() ?? 60,
        maxDays: (m?['maxDays'] as num?)?.round() ?? 30,
        leadMinutes: (m?['leadMinutes'] as num?)?.round() ?? 60,
        freeCancelHours: freeCancelHours,
      );

  Map<String, int> toMap() => {'minMinutes': minMinutes, 'maxDays': maxDays, 'leadMinutes': leadMinutes};
}

/// Pure helpers for scheduled pickups.
class Schedule {
  Schedule._();

  static ScheduleProblem? check(DateTime scheduledAt, DateTime now, ScheduleRules r) {
    if (scheduledAt.isBefore(now.add(Duration(minutes: r.minMinutes)))) return ScheduleProblem.tooSoon;
    if (scheduledAt.isAfter(now.add(Duration(days: r.maxDays)))) return ScheduleProblem.tooFar;
    return null;
  }

  /// When a scheduled booking becomes active (shown as the current trip).
  static DateTime activatesAt(DateTime scheduledAt, ScheduleRules r) => scheduledAt.subtract(Duration(minutes: r.leadMinutes));

  /// True while a scheduled booking is still in the "upcoming" list: it has a
  /// time, has not been started, and its activation moment is in the future.
  static bool isUpcoming({required DateTime? scheduledAt, required String status, required DateTime now, required ScheduleRules r}) =>
      scheduledAt != null && status == BookingStatus.accepted && now.isBefore(activatesAt(scheduledAt, r));

  /// Whole free-cancel window left: cancelling at [now] is free.
  static bool freeToCancel(DateTime scheduledAt, DateTime now, ScheduleRules r) =>
      !now.isAfter(scheduledAt.subtract(Duration(hours: r.freeCancelHours)));

  /// The slot a time of day falls in (for the older slot-based screens).
  static String slotFor(DateTime t) {
    final h = t.hour;
    if (h < 11) return PickupSlot.morning;
    if (h < 14) return PickupSlot.midday;
    if (h < 17) return PickupSlot.afternoon;
    return PickupSlot.evening;
  }

  /// "in 2 d 3 h" / "in 45 min" / "now" for a countdown line.
  static ({int days, int hours, int minutes}) until(DateTime target, DateTime now) {
    final d = target.difference(now);
    if (d.isNegative) return (days: 0, hours: 0, minutes: 0);
    return (days: d.inDays, hours: d.inHours % 24, minutes: d.inMinutes % 60);
  }
}
