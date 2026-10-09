import 'fare_calculator.dart';

/// What cancelling would cost, in words a customer can check before booking
/// (MASTER-6 Task 17). Pure: the same policy the app records a charge with.
class CancelPreview {
  /// Minutes after a driver accepts during which cancelling is free.
  final int freeMinutes;

  /// Charge in paise after that (percent of the fare, within the min and max).
  final int chargePaise;
  final num chargePercent;
  final int minCharge;
  final int maxCharge;

  /// Scheduled bookings: free until this many hours before pickup.
  final int scheduledFreeHours;

  const CancelPreview({
    required this.freeMinutes,
    required this.chargePaise,
    required this.chargePercent,
    required this.minCharge,
    required this.maxCharge,
    required this.scheduledFreeHours,
  });

  /// [farePaise] is the estimated total, the base a real cancellation is charged on (agreed fare, else this).
  static CancelPreview of(CancellationPolicy p, {required int? farePaise}) => CancelPreview(
        freeMinutes: p.freeMinutes,
        chargePaise: p.chargeFor(elapsed: Duration(minutes: p.freeMinutes), farePaise: farePaise),
        chargePercent: p.chargePercent,
        minCharge: p.minCharge,
        maxCharge: p.maxCharge,
        scheduledFreeHours: p.scheduledFreeHours,
      );

  /// Cancelling a load nobody has accepted yet never costs anything.
  static const openLoadCharge = 0;
}
