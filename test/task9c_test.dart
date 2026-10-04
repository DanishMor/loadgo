import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/geo/trip_watcher.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/matching/load_ranker.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/match_service.dart';
import 'package:transport_app/driver/trip_geofence_banner.dart';


Load load(String pickup, String drop) => Load(
      id: 'l', shipperId: 'c', pickup: pickup, drop: drop, cargoType: 'FMCG', weight: 8, vehicleType: '20ft',
      budget: 1000, pickupDate: null, notes: '', status: 'open',
    );

void main() {
  group('M14 / T8 / T10 / T11 geofence logic', () {
    test('a geofence is a circle', () {
      const g = Geofence(28.61, 77.21, 5);
      expect(g.contains(28.62, 77.22), isTrue);
      expect(g.contains(28.9, 77.21), isFalse);
    });

    final t0 = DateTime(2026, 10, 8, 10);

    test('far from the drop: no signals; about 20 km: near; inside 5 km: reached', () {
      final w = TripWatcher(dropPlace: 'Jaipur');
      w.add(t0, 28.61, 77.21); // Delhi, ~240 km
      var s = w.signals(t0);
      expect((s.nearDestination, s.destinationReached, s.longHalt), (false, false, false));
      expect(s.kmToDrop, closeTo(237, 15));
      w.add(t0.add(const Duration(minutes: 1)), 26.75, 75.8); // ~20 km from Jaipur centre
      s = w.signals(t0.add(const Duration(minutes: 1)));
      expect(s.nearDestination, isTrue);
      expect(s.destinationReached, isFalse);
      w.add(t0.add(const Duration(minutes: 2)), 26.92, 75.79);
      s = w.signals(t0.add(const Duration(minutes: 2)));
      expect(s.destinationReached, isTrue);
      expect(s.nearDestination, isFalse, reason: 'reached replaces near');
    });

    test('an unknown drop city gives no destination signals', () {
      final w = TripWatcher(dropPlace: 'Some village')..add(t0, 28.6, 77.2);
      final s = w.signals(t0);
      expect(s.kmToDrop, isNull);
      expect(s.nearDestination || s.destinationReached, isFalse);
    });

    test('long halt: standing within 300 m for 30 minutes; moving or too short does not count', () {
      final w = TripWatcher(dropPlace: 'Jaipur');
      for (var m = 0; m <= 30; m += 5) {
        w.add(t0.add(Duration(minutes: m)), 27.5, 76.5 + (m % 10) * 0.0001);
      }
      expect(w.signals(t0.add(const Duration(minutes: 30))).longHalt, isTrue);

      final short = TripWatcher(dropPlace: 'Jaipur');
      for (var m = 0; m <= 20; m += 5) {
        short.add(t0.add(Duration(minutes: m)), 27.5, 76.5);
      }
      expect(short.signals(t0.add(const Duration(minutes: 20))).longHalt, isFalse);

      final moving = TripWatcher(dropPlace: 'Jaipur');
      for (var m = 0; m <= 30; m += 5) {
        moving.add(t0.add(Duration(minutes: m)), 27.5 + m * 0.01, 76.5);
      }
      expect(moving.signals(t0.add(const Duration(minutes: 30))).longHalt, isFalse);
    });

    test('time passing without new samples still counts as a halt', () {
      final w = TripWatcher(dropPlace: 'Jaipur')..add(t0, 27.5, 76.5);
      expect(w.signals(t0.add(const Duration(minutes: 10))).longHalt, isFalse);
      expect(w.signals(t0.add(const Duration(minutes: 31))).longHalt, isTrue);
    });

    test('a halt at the drop is not a halt', () {
      final w = TripWatcher(dropPlace: 'Jaipur');
      for (var m = 0; m <= 30; m += 5) {
        w.add(t0.add(Duration(minutes: m)), 26.92, 75.79);
      }
      final s = w.signals(t0.add(const Duration(minutes: 30)));
      expect(s.destinationReached, isTrue);
      expect(s.longHalt, isFalse);
    });

    testWidgets('banner shows the near-destination alert from a position stream', (tester) async {
      languageNotifier.value = AppLanguage.english;
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: Scaffold(body: TripGeofenceBanner(dropPlace: 'Jaipur', positions: Stream.value((lat: 26.75, lng: 75.8))))),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('geoNear')), findsOneWidget);
      expect(find.textContaining('tell the receiver to get ready'), findsOneWidget);
    });

    testWidgets('banner shows reached', (tester) async {
      languageNotifier.value = AppLanguage.english;
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: Scaffold(body: TripGeofenceBanner(dropPlace: 'Jaipur', positions: Stream.value((lat: 26.92, lng: 75.79))))),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('geoReached')), findsOneWidget);
    });
  });

  group('L5 planned route', () {
    const route = PlannedRoute(from: 'Delhi', to: 'Mumbai');
    final now = DateTime(2026, 10, 4);
    final vehicle = Vehicle(id: 'v', ownerId: 'd', number: 'X', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active');
    DriverContext ctx({PlannedRoute? r}) => DriverContext(vehicles: [vehicle], now: now, plannedRoute: r);

    test('loads that start and end near the route fit; others do not', () {
      expect(route.fits(load('Delhi', 'Mumbai')), isTrue);
      expect(route.fits(load('Faridabad', 'Navi Mumbai')), isTrue);
      expect(route.fits(load('Delhi', 'Chennai')), isFalse);
      expect(route.fits(load('Pune', 'Mumbai')), isFalse);
      expect(route.fits(load('Some village', 'Mumbai')), isFalse);
    });

    test('the ranker adds a bonus and a reason', () {
      final on = LoadRanker.matchFor(load('Delhi', 'Mumbai'), ctx(r: route))!;
      final off = LoadRanker.matchFor(load('Delhi', 'Mumbai'), ctx())!;
      expect(on.reasons, contains(MatchReason.onYourRoute));
      expect(on.score, off.score + 35);
      expect(LoadRanker.matchFor(load('Delhi', 'Chennai'), ctx(r: route))!.reasons, isNot(contains(MatchReason.onYourRoute)));
    });

    test('saved on the profile, read into the driver context, cleared again', () async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'd1');
      await db.collection('users').doc('d1').set({'verified': true});
      await MatchService.setPlannedRoute(from: 'Delhi', to: 'Mumbai');
      final c = await MatchService.driverContext(now: now);
      expect(c.plannedRoute!.from, 'Delhi');
      expect(c.plannedRoute!.to, 'Mumbai');
      await MatchService.setPlannedRoute();
      expect((await MatchService.driverContext(now: now)).plannedRoute, isNull);
      expect(() => MatchService.setPlannedRoute(from: 'D', to: 'Mumbai'), throwsArgumentError);
      expect(PlannedRoute.fromUser({'plannedRoute': {'from': '', 'to': 'X'}}), isNull);
      expect(PlannedRoute.fromUser({'plannedRoute': {'from': 'A', 'to': 'B', 'date': Timestamp.fromDate(now)}})!.date, now);
    });
  });
}
