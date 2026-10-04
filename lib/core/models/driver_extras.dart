import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import 'booking.dart';
import 'earnings.dart';

/// A tip the customer recorded for the driver after delivery (paise).
/// Record only: the customer pays the driver directly.
class Tip {
  final String bookingId;
  final String driverId;
  final int amountPaise;
  final DateTime? createdAt;

  const Tip({required this.bookingId, required this.driverId, required this.amountPaise, this.createdAt});

  /// Largest tip, in paise (Rs 5000).
  static const maxPaise = 500000;

  /// Quick amounts shown to the customer, in paise.
  static const quickAmounts = [2000, 5000, 10000];

  factory Tip.fromDoc(String id, Map<String, dynamic> d) => Tip(
        bookingId: id,
        driverId: d['driverId'] as String? ?? '',
        amountPaise: (d['amountPaise'] as num?)?.toInt() ?? 0,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );

  static int total(Iterable<Tip> tips) => tips.fold(0, (a, t) => a + t.amountPaise);
}

/// `incentives/{id}`, made by an admin: deliver [targetTrips] trips within
/// [windowDays] days of [startsAt] and earn [bonusPaise].
class Incentive {
  final String id;
  final String title;
  final int targetTrips;
  final int windowDays;
  final int bonusPaise;
  final DateTime startsAt;
  final bool active;

  const Incentive({
    required this.id,
    required this.title,
    required this.targetTrips,
    required this.windowDays,
    required this.bonusPaise,
    required this.startsAt,
    this.active = true,
  });

  /// Days after the window closes during which the bonus can still be claimed.
  static const claimGraceDays = 7;

  factory Incentive.fromDoc(String id, Map<String, dynamic> d) => Incentive(
        id: id,
        title: d['title'] as String? ?? '',
        targetTrips: (d['targetTrips'] as num?)?.toInt() ?? 1,
        windowDays: (d['windowDays'] as num?)?.toInt() ?? 1,
        bonusPaise: (d['bonusPaise'] as num?)?.toInt() ?? 0,
        startsAt: (d['startsAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
        active: d['active'] == true,
      );

  Map<String, Object> toMap() => {
        'title': title,
        'targetTrips': targetTrips,
        'windowDays': windowDays,
        'bonusPaise': bonusPaise,
        'startsAt': Timestamp.fromDate(startsAt),
        'active': active,
      };

  DateTime get endsAt => startsAt.add(Duration(days: windowDays));

  /// Trips delivered inside the window, counted from the driver's bookings.
  int tripsDone(Iterable<Booking> bookings) => bookings.where((b) {
        if (b.status != BookingStatus.delivered) return false;
        final at = EarningsSummary.deliveredAt(b);
        return !at.isBefore(startsAt) && !at.isAfter(endsAt);
      }).length;

  /// 0..1 for a progress bar.
  double progress(Iterable<Booking> bookings) => (tripsDone(bookings) / targetTrips).clamp(0, 1).toDouble();

  bool reached(Iterable<Booking> bookings) => tripsDone(bookings) >= targetTrips;

  /// The window has started and not ended (progress is still counting).
  bool isRunning(DateTime now) => active && !now.isBefore(startsAt) && now.isBefore(endsAt);

  /// A reached target can be claimed until [claimGraceDays] after the window.
  bool canClaim(Iterable<Booking> bookings, DateTime now) =>
      active && !now.isBefore(startsAt) && !now.isAfter(endsAt.add(const Duration(days: claimGraceDays))) && reached(bookings);
}

/// A driver's claim for an [Incentive]; the id is `{incentiveId}_{driverId}`
/// so a bonus can be claimed once. `paid` is set by an admin by hand.
class IncentiveClaim {
  final String id;
  final String incentiveId;
  final String driverId;
  final int bonusPaise;
  final String status;
  final DateTime? createdAt;

  const IncentiveClaim({
    required this.id,
    required this.incentiveId,
    required this.driverId,
    required this.bonusPaise,
    required this.status,
    this.createdAt,
  });

  static const claimed = 'claimed';
  static const paid = 'paid';

  factory IncentiveClaim.fromDoc(String id, Map<String, dynamic> d) => IncentiveClaim(
        id: id,
        incentiveId: d['incentiveId'] as String? ?? '',
        driverId: d['driverId'] as String? ?? '',
        bonusPaise: (d['bonusPaise'] as num?)?.toInt() ?? 0,
        status: d['status'] as String? ?? claimed,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// Driver plan: Free or Pro. Pro pays a lower platform commission. There is
/// no payment yet (LATER(paid)): a driver can only request Pro and an admin
/// grants it by hand (`users.plan`, `users.planUntil`; owners cannot write
/// those fields).
class DriverPlan {
  DriverPlan._();
  static const free = 'free';
  static const pro = 'pro';

  static const requestPending = 'pending';
  static const requestApproved = 'approved';
  static const requestRejected = 'rejected';

  /// True while the user's profile carries an unexpired Pro plan.
  static bool isPro(Map<String, dynamic>? user, DateTime now) {
    if (user?['plan'] != pro) return false;
    final until = (user?['planUntil'] as Timestamp?)?.toDate();
    return until == null || until.isAfter(now);
  }
}
