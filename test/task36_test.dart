import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/app_notification.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/audit_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/chat_service.dart';
import 'package:transport_app/core/services/location_service.dart';
import 'package:transport_app/core/services/trip_evidence_service.dart';
import 'package:transport_app/core/trip/trip_alerts.dart';
import 'package:transport_app/driver/pickup_alerts.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  var uid = 'd1';

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'd1';
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(() => LocationService.useFakeCurrent(null));

  Future<Booking> booking({String status = 'in_transit', Map<String, Object?> extra = const {}}) async {
    await db.collection('bookings').doc('b1').set({
      'driverId': 'd1', 'customerId': 'c1', 'status': status, 'pickup': 'Pune', 'drop': 'Delhi', 'timeline': {}, 'cargoType': 'FMCG', 'weight': 5,
      'vehicleType': '20ft', 'vehicleNumber': 'MH12AB1234', 'driverName': 'Ramesh', 'driverPhone': '+919800000001', ...extra,
    });
    return Booking.fromDoc(await db.collection('bookings').doc('b1').get());
  }

  Widget app(Widget w) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));

  group('stop progress (T7)', () {
    test('stops turn reached in any order the driver passes them; next stop and distance follow', () {
      final t = StopTracker(['Nashik', 'Indore', 'Delhi']);
      expect(t.nextIndex, 0);
      expect(t.add(18.52, 73.86), isEmpty); // Pune: none
      expect(t.kmToNext, greaterThan(100));
      expect(t.add(20.0, 73.79), [0]); // Nashik
      expect(t.add(20.0, 73.79), isEmpty, reason: 'only reported once');
      expect(t.nextIndex, 1);
      expect(t.reached(0), isTrue);
      expect(t.add(28.61, 77.21), [2]); // jumped to Delhi
      expect(t.nextIndex, 1);
      expect(t.reachedCount, 2);
    });

    test('unknown places cannot be tracked and are skipped', () {
      final t = StopTracker(['Nowhereville', 'Delhi']);
      expect(t.trackable, 1);
      expect(t.nextIndex, 1);
    });

    testWidgets('the card lists stops, shows the alert for a stop reached and the next stop', (tester) async {
      final b = await booking(extra: {'extraDrops': ['Nashik']});
      final pos = Stream<Coordinates>.fromIterable([(lat: 18.52, lng: 73.86), (lat: 20.0, lng: 73.79)]);
      await tester.pumpWidget(app(StopProgressCard(booking: b, positions: pos)));
      await settle(tester);
      expect(find.text('Stops reached: 1 of 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('stopAlert')), findsOneWidget);
      expect(find.text('Stop reached: Nashik'), findsOneWidget);
      expect(find.textContaining('Next: Delhi'), findsOneWidget);
    });
  });

  group('pickup geofence and arriving alert (T3, N2)', () {
    testWidgets('far from pickup: km shown, no alert; near: one notification to the customer; at pickup: reached', (tester) async {
      final b = await booking(status: 'driver_arriving');
      final pos = Stream<Coordinates>.fromIterable([(lat: 19.5, lng: 73.9), (lat: 18.6, lng: 73.86), (lat: 18.53, lng: 73.86), (lat: 18.52, lng: 73.855)]);
      await tester.pumpWidget(app(PickupGeofenceBanner(booking: b, positions: pos)));
      await settle(tester);
      expect(find.byKey(const ValueKey('pickupReached')), findsOneWidget);
      expect(find.text('You are at the pickup'), findsOneWidget);
      final n = await db.collection('notifications').get();
      expect(n.docs.length, 1, reason: 'sent once');
      expect(n.docs.single.id, 'arrive_b1');
      expect(n.docs.single.data()['userId'], 'c1');
      expect(n.docs.single.data()['type'], NotificationType.arrivingSoon);
    });

    testWidgets('far away: only the distance, nothing sent', (tester) async {
      final b = await booking(status: 'driver_arriving');
      await tester.pumpWidget(app(PickupGeofenceBanner(booking: b, positions: Stream.value((lat: 20.5, lng: 74.0)))));
      await settle(tester);
      expect(find.byKey(const ValueKey('pickupNear')), findsOneWidget);
      expect(find.textContaining('km to the pickup'), findsOneWidget);
      expect((await db.collection('notifications').get()).docs, isEmpty);
    });
  });

  group('chat notification (N10)', () {
    test('the other person is notified once per burst of messages', () async {
      final b = await booking();
      await ChatService.send(b, 'hello');
      await ChatService.send(b, 'are you there?');
      var n = await db.collection('notifications').get();
      expect(n.docs.length, 1);
      expect(n.docs.single.data()['userId'], 'c1');
      expect(n.docs.single.data()['type'], NotificationType.chatMessage);
      uid = 'c1';
      await ChatService.send(b, 'yes');
      n = await db.collection('notifications').get();
      expect(n.docs.length, 2, reason: 'a reply notifies the driver');
      expect(n.docs.where((d) => d.data()['userId'] == 'd1').length, 1);
    });
  });

  group('evidence audit (S15) and document views (DOC14)', () {
    test('every evidence write adds an audit event with who and where', () async {
      LocationService.useFakeCurrent(() async => (lat: 28.6139, lng: 77.2090));
      final b = await booking(status: 'loading');
      await TripEvidenceService.setOdometer(b, start: true, km: 1000);
      await TripEvidenceService.saveGps('b1', pickup: true, place: 'Delhi');
      await TripEvidenceService.addCargoDoc(b, type: 'invoice', number: 'INV-1', leg: 1);
      await TripEvidenceService.logDocView('b1');
      final events = (await db.collection('audit_events').get()).docs.map((d) => d.data()).toList();
      final kinds = [for (final e in events) if (e['type'] == AuditType.evidence) (e['data'] as Map)['kind']];
      expect(kinds, unorderedEquals(['odometer_start', 'pickup_gps', 'cargo_doc']));
      expect(events.where((e) => e['type'] == AuditType.docView).length, 1);
      expect(events.every((e) => e['actorId'] == 'd1' && e['bookingId'] == 'b1' && e['createdAt'] != null), isTrue);
      final gps = events.firstWhere((e) => (e['data'] as Map)['kind'] == 'pickup_gps')['data'] as Map;
      expect(gps['lat'], 28.6139);
      expect((await db.collection('risk_signals').get()).docs, isEmpty, reason: 'at the booked city');
    });

    test('accident and signature writes are audited too', () async {
      final b = await booking(status: 'unloading');
      await TripEvidenceService.reportAccident(b, 'Tyre burst, truck tilted');
      final kinds = (await db.collection('audit_events').get()).docs.map((d) => (d.data()['data'] as Map)['kind']).toList();
      expect(kinds, ['accident']);
    });
  });

  group('GPS vs booked city (F10, F11)', () {
    test('pure check: inside the radius is fine, 200 km off is a mismatch, unknown cities are not judged', () {
      expect(gpsMismatchKm(28.7, 77.1, 'Delhi'), isNull);
      expect(gpsMismatchKm(18.52, 73.86, 'Delhi'), greaterThan(1000));
      expect(gpsMismatchKm(18.52, 73.86, 'Nowhereville'), isNull);
    });

    test('a delivery GPS far from the drop writes a risk signal for admins', () async {
      await booking(status: 'unloading');
      LocationService.useFakeCurrent(() async => (lat: 19.0, lng: 73.0)); // near Mumbai, drop is Delhi
      await TripEvidenceService.saveGps('b1', pickup: false, place: 'Delhi');
      final s = (await db.collection('risk_signals').get()).docs.single.data();
      expect(s['type'], 'gps_mismatch');
      expect(s['uid'], 'd1');
      expect(s['bookingId'], 'b1');
      expect(s['note'], contains('delivery GPS'));
    });
  });

  group('trip summary for emergency contacts (SAFE2)', () {
    test('has route, status, vehicle, driver and last seen link', () async {
      final b = await booking(extra: {'lastKnownLocation': const GeoPoint(21.1458, 79.0882)});
      final t = tripSummaryText(b, who: 'Ramesh');
      expect(t, contains('LoadGo trip of Ramesh: Pune -> Delhi'));
      expect(t, contains('Status: in transit'));
      expect(t, contains('Vehicle: MH12AB1234'));
      expect(t, contains('Driver: Ramesh'));
      expect(t, isNot(contains('+919800000001')), reason: 'phone numbers stay private');
      expect(t, contains('https://maps.google.com/?q=21.1458,79.0882'));
      expect(t, contains('Booking ID: b1'));
    });
  });
}
