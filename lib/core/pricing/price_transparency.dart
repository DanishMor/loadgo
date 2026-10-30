import 'fare_calculator.dart';
import 'route_rates.dart';

/// E27: the promise behind the price card: every rupee of the total is a line the customer can see. The guard
/// test (test/price_transparency_test.dart) keeps [chargeKeys] equal to the money fields of [FareBreakdown.toMap]
/// and checks that the fare breakdown view shows each of them, so a new fee cannot be added without a line.
class PriceTransparency {
  PriceTransparency._();

  /// Every charge that makes up [FareBreakdown.total], by its toMap key.
  static const chargeKeys = [
    'baseFare',
    'distanceCharge',
    'loadingCharge',
    'unloadingCharge',
    'waitingCharge',
    'extraStopCharge',
    'helperCharge',
    'rentalCharge',
    'extraKmCharge',
    'extraHourCharge',
    'itemHandlingCharge',
    'floorCharge',
    'packingCharge',
    'minimumFareAdjustment',
    'surgeCharge',
    'platformFee',
    'gst',
  ];

  /// Fields of toMap that are not money added to the total (sizes, rates, sums).
  static const notCharges = {'distanceKm', 'surgePercent', 'surgeKind', 'platformFeePercent', 'gstPercent', 'tripFare', 'total'};

  /// The charges of [f] as (key, paise), zero lines left out.
  static List<(String, int)> lines(FareBreakdown f) {
    final m = f.toMap();
    return [for (final k in chargeKeys) if ((m[k] as num? ?? 0) != 0) (k, (m[k] as num).round())];
  }

  /// True when the shown lines add up to the total, to the paisa.
  static bool addsUp(FareBreakdown f) => lines(f).fold<int>(0, (a, l) => a + l.$2) == f.total;
}

/// Where a price sits against what customers paid on the same route lately.
enum FairPosition { unknown, below, usual, above }

FairPosition fairPosition(int pricePaise, RateRange? range) {
  if (range == null || range.low <= 0 || range.high < range.low) return FairPosition.unknown;
  if (pricePaise < range.low) return FairPosition.below;
  if (pricePaise > range.high) return FairPosition.above;
  return FairPosition.usual;
}
