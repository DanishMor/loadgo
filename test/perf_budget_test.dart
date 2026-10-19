import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/matching/load_ranker.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/services/breadcrumbs.dart';

/// Part 5 (H29): speed budgets for the pure Dart hot paths, written as tests so a slow change fails the build.
/// The limits are about 10 times what a laptop needs, so they only fail on a real slowdown (a loop inside a loop,
/// a regex that backtracks), not on a busy machine. docs/PERFORMANCE.md lists them.
void main() {
  T timed<T>(String what, int budgetMs, T Function() run) {
    final clock = Stopwatch()..start();
    final r = run();
    clock.stop();
    // ignore: avoid_print
    print('PERF $what: ${clock.elapsedMilliseconds} ms (budget $budgetMs ms)');
    expect(clock.elapsedMilliseconds, lessThan(budgetMs), reason: '$what took ${clock.elapsedMilliseconds} ms');
    return r;
  }

  test('fare: 20 000 quotes under 1.5 s, always whole non-negative paise', () {
    timed('fare x20000', 1500, () {
      for (var i = 0; i < 20000; i++) {
        final f = FareCalculator.calculate(
          rule: const PricingRule(baseFare: 50000, perKm: 2800, minimumFare: 80000, loadingCharge: 20000, unloadingCharge: 20000),
          distanceKm: i % 1500,
          platformFeePercent: 5,
          gstPercent: 5,
          helpers: i % 5,
        );
        if (f.total < 0 || f.total != f.tripFare + f.platformFee + f.gst) throw StateError('bad fare at $i');
      }
    });
  });

  test('log cleaning: 3 000 lines of 200 characters with phones, ids and codes under 4 s', () {
    final line = 'Bad state for 9876543210 booking MH12AB1234 code 654321 mail a.b@c.in key rzp_live_AbCdEf1234 ${'word ' * 25}';
    timed('redactor x3000', 4000, () {
      for (var i = 0; i < 3000; i++) {
        Redactor.safe(line);
      }
    });
  });

  group('lists of documents', () {
    late List<QueryDocumentSnapshot<Map<String, dynamic>>> loadDocs;
    late List<Vehicle> vehicles;

    setUpAll(() async {
      final db = FakeFirebaseFirestore();
      final cities = ['Delhi', 'Jaipur', 'Mumbai', 'Pune', 'Ahmedabad', 'Surat', 'Lucknow', 'Kanpur', 'Indore', 'Bhopal'];
      for (var i = 0; i < 1500; i++) {
        await db.collection('loads').doc('L$i').set({
          'shipperId': 'c${i % 50}', 'pickup': cities[i % 10], 'drop': cities[(i * 3 + 1) % 10], 'cargoType': 'FMCG', 'weight': 1 + i % 9, 'vehicleType': '14ft',
          'budget': 10000 + i, 'pickupDate': Timestamp.fromDate(DateTime.now().add(Duration(days: i % 7))), 'notes': '', 'status': 'open', 'createdAt': Timestamp.now(),
        });
      }
      for (var i = 0; i < 3; i++) {
        await db.collection('vehicles').doc('v$i').set({'ownerId': 'd1', 'number': 'MH12AB12$i', 'type': '14ft', 'capacity': 12, 'status': 'active', 'rcNumber': 'RC$i'});
      }
      loadDocs = (await db.collection('loads').get()).docs;
      vehicles = (await db.collection('vehicles').get()).docs.map(Vehicle.fromDoc).toList();
    });

    test('reading 1 500 loads under 1 s', () {
      final loads = timed('Load.fromDoc x1500', 1000, () => loadDocs.map(Load.fromDoc).toList());
      expect(loads.length, 1500);
    });

    test('ranking 1 500 open loads for a driver with 3 vehicles under 2 s', () {
      final loads = loadDocs.map(Load.fromDoc).toList();
      final ctx = DriverContext(vehicles: vehicles, anchorPlace: 'Delhi', now: DateTime.now());
      final ranked = timed('rank x1500', 2000, () => LoadRanker.rank(loads, ctx));
      expect(ranked, isNotEmpty);
      // the order is by score, best first
      for (var i = 1; i < ranked.length; i++) {
        expect(ranked[i - 1].score, greaterThanOrEqualTo(ranked[i].score));
      }
    });
  });
}
