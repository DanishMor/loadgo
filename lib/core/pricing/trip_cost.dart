/// Offline toll, fuel and trip cost estimates. Every figure is an estimate
/// (integer paise). LATER(paid): real toll plazas and live diesel price.
library;

import 'cities.dart';

const _categories = ['two_wheeler', 'three_wheeler', 'lcv', 'hcv', 'container', 'trailer'];

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

/// Toll per vehicle category: a per-km average for any route and fixed
/// figures for the busiest corridors (given for an LCV, scaled per category).
class TollTable {
  TollTable._();

  /// Average toll in paise per km (over a whole route, not only plaza km).
  static const perKmPaise = <String, int>{
    'two_wheeler': 0,
    'three_wheeler': 0,
    'lcv': 120,
    'hcv': 240,
    'container': 360,
    'trailer': 480,
  };

  /// Multiplier of the LCV corridor figure, in percent.
  static const _categoryPercent = <String, int>{
    'two_wheeler': 0,
    'three_wheeler': 0,
    'lcv': 100,
    'hcv': 200,
    'container': 300,
    'trailer': 400,
  };

  /// LCV toll for top corridors (paise), key = the two city names sorted.
  static const _corridorLcv = <String, int>{
    'Delhi|Jaipur': 70000,
    'Agra|Delhi': 60000,
    'Delhi|Lucknow': 110000,
    'Chandigarh|Delhi': 40000,
    'Delhi|Mumbai': 330000,
    'Mumbai|Pune': 60000,
    'Ahmedabad|Mumbai': 90000,
    'Ahmedabad|Vadodara': 25000,
    'Bengaluru|Chennai': 70000,
    'Bengaluru|Hyderabad': 80000,
    'Hyderabad|Pune': 90000,
    'Jaipur|Ahmedabad': 85000,
    'Kolkata|Patna': 80000,
    'Indore|Mumbai': 90000,
    'Bhopal|Indore': 25000,
  };

  static String _key(String a, String b) {
    final s = [a, b]..sort();
    return s.join('|');
  }

  static String _cat(String category) => _categories.contains(category) ? category : 'lcv';

  /// Fixed corridor figure for the pair, or null when it is not in the table.
  static int? corridor(String fromCity, String toCity, String category) {
    final lcv = _corridorLcv[_key(fromCity, toCity)];
    if (lcv == null) return null;
    return (lcv * _categoryPercent[_cat(category)]! / 100).round();
  }

  /// Toll estimate for [km] between two places. A known corridor uses its
  /// fixed figure; anything else falls back to the per-km average. The
  /// corridor figure is clamped to at most 3x the per-km figure so a wrong distance cannot give a silly number.
  static int estimate({required String from, required String to, required String category, required int km}) {
    if (km <= 0) return 0;
    final cat = _cat(category);
    final byKm = perKmPaise[cat]! * km;
    final a = findCity(from), b = findCity(to);
    if (a != null && b != null) {
      final fixed = corridor(a.name, b.name, cat);
      if (fixed != null) return byKm > 0 ? fixed.clamp(0, byKm * 3) : fixed;
    }
    return byKm;
  }
}

/// Diesel use: kilometres per litre by category (tenths: 40 = 4.0 km/l).
class FuelEstimate {
  FuelEstimate._();

  static const defaultDieselPaisePerLitre = 9000;

  static const mileageTenths = <String, int>{
    'two_wheeler': 400,
    'three_wheeler': 250,
    'lcv': 120,
    'hcv': 40,
    'container': 35,
    'trailer': 30,
  };

  static int litresTenths(int km, String category) {
    if (km <= 0) return 0;
    final m = mileageTenths[_categories.contains(category) ? category : 'lcv']!;
    return _ceilDiv(km * 100, m);
  }

  /// Fuel cost for [km] at [dieselPaisePerLitre], rounded half up.
  static int cost({required int km, required String category, int dieselPaisePerLitre = defaultDieselPaisePerLitre}) {
    if (km <= 0 || dieselPaisePerLitre <= 0) return 0;
    final m = mileageTenths[_categories.contains(category) ? category : 'lcv']!;
    // km / (m/10 km per litre) * price, in integer maths, half up.
    return (km * 10 * dieselPaisePerLitre + m ~/ 2) ~/ m;
  }
}

/// Fare, toll and fuel for one trip. All paise and all estimates.
class TripCostPreview {
  final int farePaise;
  final int tollPaise;
  final int fuelPaise;

  const TripCostPreview({required this.farePaise, required this.tollPaise, required this.fuelPaise});

  factory TripCostPreview.compute({
    required int farePaise,
    required int km,
    required String category,
    required String from,
    required String to,
    int dieselPaisePerLitre = FuelEstimate.defaultDieselPaisePerLitre,
  }) =>
      TripCostPreview(
        farePaise: farePaise,
        tollPaise: TollTable.estimate(from: from, to: to, category: category, km: km),
        fuelPaise: FuelEstimate.cost(km: km, category: category, dieselPaisePerLitre: dieselPaisePerLitre),
      );

  /// Fare + toll + fuel, the full cost picture of the trip.
  int get total => farePaise + tollPaise + fuelPaise;

  /// What the driver's running costs take out of the fare.
  int get runningCost => tollPaise + fuelPaise;

  /// What is left of [farePaise] after toll and fuel (can be negative).
  int get netMargin => farePaise - runningCost;

  /// The same trip priced at another amount (a bid).
  TripCostPreview withFare(int paise) => TripCostPreview(farePaise: paise, tollPaise: tollPaise, fuelPaise: fuelPaise);
}
