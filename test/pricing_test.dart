import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/pricing/cities.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/pricing/pricing_config.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/widgets/common.dart';

void main() {
  tearDown(PricingService.reset);

  const rule = PricingRule(
    baseFare: 50000, perKm: 2800, minimumFare: 80000, loadingCharge: 20000, unloadingCharge: 20000,
    waitingPerHour: 30000, perExtraStop: 15000,
  );

  group('FareCalculator', () {
    test('adds every component, then platform fee and GST on top', () {
      final f = FareCalculator.calculate(rule: rule, distanceKm: 100, platformFeePercent: 5, gstPercent: 5);
      expect(f.distanceCharge, 280000);
      expect(f.tripFare, 50000 + 280000 + 20000 + 20000);
      expect(f.platformFee, 18500); // 5% of 370000
      expect(f.gst, 19425); // 5% of 388500
      expect(f.total, 370000 + 18500 + 19425);
      expect(f.minimumFareAdjustment, 0);
    });

    test('short trips are topped up to the minimum fare', () {
      final f = FareCalculator.calculate(rule: rule, distanceKm: 0, loading: false, unloading: false);
      expect(f.minimumFareAdjustment, 30000);
      expect(f.tripFare, 80000);
      expect(f.total, 80000);
    });

    test('waiting is billed per started hour; extra stops are added', () {
      final f = FareCalculator.calculate(rule: rule, distanceKm: 10, waitingMinutes: 61, extraStops: 2);
      expect(f.waitingCharge, 60000);
      expect(f.extraStopCharge, 30000);
      expect(FareCalculator.calculate(rule: rule, distanceKm: 10, waitingMinutes: 0).waitingCharge, 0);
    });

    test('percentages round half-up to whole paise', () {
      const r = PricingRule(baseFare: 333, perKm: 0, minimumFare: 0);
      final f = FareCalculator.calculate(rule: r, distanceKm: 0, platformFeePercent: 2.5, gstPercent: 18, loading: false, unloading: false);
      expect(f.platformFee, 8); // 8.325
      expect(f.gst, 61); // 18% of 341 = 61.38
      expect(f.total, 333 + 8 + 61);
    });

    test('rejects negative distance; breakdown survives a map round trip', () {
      expect(() => FareCalculator.calculate(rule: rule, distanceKm: -1), throwsArgumentError);
      final f = FareCalculator.calculate(rule: rule, distanceKm: 42, platformFeePercent: 5, gstPercent: 5);
      final back = FareBreakdown.fromMap(f.toMap());
      expect(back.total, f.total);
      expect(back.distanceKm, 42);
    });
  });

  group('CancellationPolicy', () {
    const p = CancellationPolicy(freeMinutes: 15, chargePercent: 10, minCharge: 5000, maxCharge: 100000);
    test('free window, percent of fare, clamped', () {
      expect(p.chargeFor(elapsed: const Duration(minutes: 5), farePaise: 500000), 0);
      expect(p.chargeFor(elapsed: const Duration(minutes: 20), farePaise: 500000), 50000);
      expect(p.chargeFor(elapsed: const Duration(minutes: 20), farePaise: 10000), 5000);
      expect(p.chargeFor(elapsed: const Duration(hours: 2), farePaise: 5000000), 100000);
      expect(p.chargeFor(elapsed: const Duration(hours: 2)), 5000, reason: 'no estimate -> minimum');
    });
  });

  group('PricingConfig', () {
    test('config overrides merge onto defaults; type rules beat category rules', () {
      final c = PricingConfig.fromMap({
        'platformFeePercent': 3,
        'categories': {'lcv': {'perKm': 3000}},
        'types': {'Mini': {'baseFare': 40000, 'perKm': 2000, 'minimumFare': 60000}},
        'cancellation': {'freeMinutes': 30},
      });
      expect(c.platformFeePercent, 3);
      expect(c.gstPercent, defaultPricing.gstPercent);
      expect(c.ruleFor('14ft', 'lcv').perKm, 3000);
      expect(c.ruleFor('14ft', 'lcv').baseFare, defaultPricing.categories['lcv']!.baseFare);
      expect(c.ruleFor('Mini', 'lcv').perKm, 2000);
      expect(c.ruleFor('Spaceship', 'unknown').perKm, 3000, reason: 'falls back to lcv');
      expect(c.cancellation.freeMinutes, 30);
      expect(PricingConfig.fromMap(c.toMap()).ruleFor('Mini', 'lcv').baseFare, 40000);
    });

    test('refresh reads config/pricing', () async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'u');
      await db.collection('config').doc('pricing').set({'gstPercent': 12});
      await PricingService.refresh();
      expect(PricingService.config.gstPercent, 12);
    });
  });

  group('cities', () {
    test('finds cities by name or alias inside free text', () {
      expect(findCity('Andheri East, Mumbai')!.name, 'Mumbai');
      expect(findCity('bombay')!.name, 'Mumbai');
      expect(findCity('Whitefield, Bangalore 560066')!.name, 'Bengaluru');
      expect(findCity('Sector 18, Gurgaon')!.name, 'Gurugram');
      expect(findCity('New Delhi')!.name, 'Delhi');
      expect(findCity('Nowhere village'), isNull);
      expect(indianCities.length, greaterThanOrEqualTo(60));
    });

    test('road distance = haversine x road factor', () {
      final km = PricingService.estimateKm('Delhi', 'Mumbai')!;
      expect(km, inInclusiveRange(1350, 1550)); // ~1150 km straight line
      expect(PricingService.estimateKm('Pune', 'Pune'), 15);
      expect(PricingService.estimateKm('Pune', 'Atlantis'), isNull);
    });

    test('quote uses the vehicle category rate card', () {
      final bike = PricingService.quote(vehicleType: 'Bike', distanceKm: 10);
      final trailer = PricingService.quote(vehicleType: 'Trailer', distanceKm: 10);
      expect(bike.total, lessThan(trailer.total));
    });
  });

  test('formatPaise uses Indian grouping and shows paise only when present', () {
    expect(formatPaise(0), '₹ 0');
    expect(formatPaise(12345600), '₹ 1,23,456');
    expect(formatPaise(123450), '₹ 1,234.50');
    expect(formatPaise(99), '₹ 0.99');
    expect(formatPaise(-500), '-₹ 5');
  });

  group('estimate on loads and cancellation records', () {
    late FakeFirebaseFirestore db;
    String? uid;
    setUp(() {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => uid);
    });

    Future<String> bookedLoad() async {
      uid = 'customer1';
      final quote = PricingService.quote(vehicleType: '20ft', distanceKm: 1400);
      final loadId = await LoadService.post(
          pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: null,
          pickupDate: DateTime(2026, 10, 5), notes: '', estimate: quote, distanceSource: DistanceSource.cities);
      final load = Load.fromDoc(await db.collection('loads').doc(loadId).get());
      expect(load.estimate!.total, quote.total);
      expect(load.distanceSource, 'cities');
      uid = 'driver1';
      final vid = await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
      final v = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == vid);
      return BookingService.accept(loadId: loadId, vehicle: v);
    }

    test('booking copies the estimate; early cancel records a zero charge', () async {
      final id = await bookedLoad();
      final b = Booking.fromDoc(await db.collection('bookings').doc(id).get());
      expect(b.fareEstimate, isNotNull);
      await BookingService.cancelByDriver(id);
      final after = Booking.fromDoc(await db.collection('bookings').doc(id).get());
      expect(after.cancellation!.by, 'driver');
      expect(after.cancellation!.chargePaise, 0);
    });

    test('late cancel charge follows the policy', () async {
      final id = await bookedLoad();
      final b = Booking.fromDoc(await db.collection('bookings').doc(id).get());
      final late = b.timeline['accepted']!.add(const Duration(hours: 1));
      expect(BookingService.cancellationCharge(b, late), (b.fareEstimate! * 0.10).round().clamp(5000, 100000));
    });
  });
}
