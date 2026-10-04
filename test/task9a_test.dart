import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/documents/pod_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/trip_evidence.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/location_service.dart';
import 'package:transport_app/core/services/notification_service.dart';
import 'package:transport_app/core/services/payment_service.dart';
import 'package:transport_app/core/services/trip_evidence_service.dart';
import 'package:transport_app/core/widgets/evidence_cards.dart';
import 'package:transport_app/core/widgets/signature_pad.dart';
import 'package:transport_app/driver/trip_safety_card.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String uid = 'd1';
  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'd1';
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(() => LocationService.useFakeCurrent(null));

  Future<Booking> booking({String status = 'in_transit', Map<String, Object?> extra = const {}}) async {
    await db.collection('bookings').doc('b1').set({
      'driverId': 'd1', 'customerId': 'c1', 'status': status, 'pickup': 'Delhi', 'drop': 'Jaipur', 'timeline': {}, ...extra,
    });
    return Booking.fromDoc(await db.collection('bookings').doc('b1').get());
  }

  Widget app(Widget w) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));

  group('S2 GPS evidence', () {
    test('saves the position with the pickup and delivery events; nothing without a fix', () async {
      await booking();
      LocationService.useFakeCurrent(() async => null);
      expect(await TripEvidenceService.saveGps('b1', pickup: true), isFalse);
      LocationService.useFakeCurrent(() async => (lat: 28.61, lng: 77.21));
      expect(await TripEvidenceService.saveGps('b1', pickup: true), isTrue);
      expect(await TripEvidenceService.saveGps('b1', pickup: false), isTrue);
      final b = Booking.fromDoc(await db.collection('bookings').doc('b1').get());
      expect(b.pickupGps!.latitude, 28.61);
      expect(b.deliveryGps!.longitude, 77.21);
    });
  });

  group('S6 odometer', () {
    test('start and end readings; end cannot be below start; limits', () async {
      var b = await booking(status: 'loading');
      await TripEvidenceService.setOdometer(b, start: true, km: 120500);
      b = Booking.fromDoc(await db.collection('bookings').doc('b1').get());
      expect(b.odometerStart, 120500);
      await expectLater(TripEvidenceService.setOdometer(b, start: false, km: 120400), throwsA(isA<EvidenceException>()));
      await expectLater(TripEvidenceService.setOdometer(b, start: true, km: -1), throwsA(isA<EvidenceException>()));
      await expectLater(TripEvidenceService.setOdometer(b, start: true, km: 10000000), throwsA(isA<EvidenceException>()));
      await TripEvidenceService.setOdometer(b, start: false, km: 120940);
      expect(Booking.fromDoc(await db.collection('bookings').doc('b1').get()).odometerEnd, 120940);
    });

    testWidgets('driver card: save the start reading, then it shows', (tester) async {
      final b = (await tester.runAsync(() => booking(status: 'loading')))!;
      await tester.pumpWidget(app(DriverEvidenceCard(booking: b)));
      await tester.enterText(find.byKey(const ValueKey('odoField')), '5000');
      await tester.tap(find.byKey(const ValueKey('odoSave')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('bookings').doc('b1').get()))!.data()!['odometerStart'], 5000);
      final b2 = (await tester.runAsync(() async => Booking.fromDoc(await db.collection('bookings').doc('b1').get())))!;
      await tester.pumpWidget(app(DriverEvidenceCard(booking: b2)));
      expect(find.text('Odometer at start: 5000 km'), findsOneWidget);
    });
  });

  group('S13 signature', () {
    const sig = SignatureStrokes([
      [(x: 0.1, y: 0.2), (x: 0.5, y: 0.6), (x: 0.9, y: 0.3)],
      [(x: 0.2, y: 0.8), (x: 0.7, y: 0.8)],
    ]);

    test('round trip through the Firestore form (no nested arrays)', () {
      final f = sig.toFirestore();
      expect(f, hasLength(2));
      expect(f.first['p'], [0.1, 0.2, 0.5, 0.6, 0.9, 0.3]);
      final back = SignatureStrokes.fromFirestore(f);
      expect(back.strokes.first[1], (x: 0.5, y: 0.6));
      expect(back.strokes, hasLength(2));
      expect(const SignatureStrokes([[(x: 0, y: 0)]]).isEmpty, isTrue);
      expect(const SignatureStrokes([]).isEmpty, isTrue);
    });

    test('values are clamped and rounded; size is capped', () {
      final big = SignatureStrokes([
        [for (var i = 0; i < 500; i++) (x: 1.5, y: -0.2)],
      ]);
      final p = big.toFirestore().single['p'] as List;
      expect(p.length, SignatureStrokes.maxPointsPerStroke * 2);
      expect(p.first, 1.0);
      expect(p[1], 0.0);
    });

    test('saved once by the driver while unloading or delivered', () async {
      final b = await booking(status: 'unloading');
      await expectLater(TripEvidenceService.saveSignature(b, const SignatureStrokes([])), throwsA(isA<EvidenceException>()));
      await TripEvidenceService.saveSignature(b, sig);
      expect((await TripEvidenceService.watchSignature('b1').first)!.strokes, hasLength(2));
      await expectLater(TripEvidenceService.saveSignature(b, sig), throwsA(isA<EvidenceException>().having((e) => e.reason, 'reason', 'already')));
    });

    testWidgets('the pad records strokes and the dialog returns them', (tester) async {
      SignatureStrokes? result;
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () async => result = await showSignatureDialog(context), child: const Text('sign')))))),
      ));
      await tester.tap(find.text('sign'));
      await tester.pumpAndSettle();
      final pad = find.byKey(const ValueKey('signaturePad'));
      final g = await tester.startGesture(tester.getTopLeft(pad) + const Offset(20, 20));
      await g.moveBy(const Offset(40, 30));
      await g.moveBy(const Offset(40, -10));
      await g.up();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('signatureSave')));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.strokes.single.length, greaterThanOrEqualTo(2));
      expect(result!.strokes.single.every((p) => p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1), isTrue);
    });

    testWidgets('an empty pad returns nothing', (tester) async {
      SignatureStrokes? result = const SignatureStrokes([[(x: 0, y: 0), (x: 1, y: 1)]]);
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () async => result = await showSignatureDialog(context), child: const Text('sign')))))),
      ));
      await tester.tap(find.text('sign'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('signatureSave')));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('the POD packet shows GPS, odometer and the signature', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final b = (await tester.runAsync(() async {
        final bk = await booking(status: 'delivered', extra: {'pickupGps': const GeoPoint(28.6, 77.2), 'odometerStart': 100, 'odometerEnd': 450});
        await db.collection('bookings').doc('b1').collection('signatures').doc('receiver').set({'strokes': sig.toFirestore(), 'driverId': 'd1', 'createdAt': Timestamp.now()});
        return bk;
      }))!;
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: PodScreen(booking: b))));
      await settle(tester);
      expect(find.text('28.60000, 77.20000'), findsOneWidget);
      expect(find.text('450 km'), findsOneWidget);
      expect(find.byKey(const ValueKey('signatureView')), findsOneWidget);
    });
  });

  group('DOC7 / IE13 / DOC9 cargo documents', () {
    test('records are appended; the history keeps every version; the newest per type and leg wins', () async {
      final b = await booking();
      await TripEvidenceService.addCargoDoc(b, type: CargoDocType.invoice, number: 'INV-1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await TripEvidenceService.addCargoDoc(b, type: CargoDocType.invoice, number: 'INV-1A', note: 'corrected');
      await TripEvidenceService.addCargoDoc(b, type: CargoDocType.billOfLading, number: 'BL-9', leg: 1);
      final all = await TripEvidenceService.watchCargoDocs('b1').first;
      expect(all, hasLength(3));
      final latest = CargoDoc.latestByType(all);
      expect(latest['invoice#0']!.number, 'INV-1A');
      expect(latest['bill_of_lading#1']!.number, 'BL-9');
      expect(all.first.number, 'INV-1', reason: 'old versions stay');
    });

    test('bad records are refused', () async {
      final b = await booking();
      await expectLater(TripEvidenceService.addCargoDoc(b, type: 'passport', number: 'X'), throwsArgumentError);
      await expectLater(TripEvidenceService.addCargoDoc(b, type: 'invoice', number: ''), throwsA(isA<EvidenceException>()));
      await expectLater(TripEvidenceService.addCargoDoc(b, type: 'invoice', number: 'x' * 41), throwsA(isA<EvidenceException>()));
      await expectLater(TripEvidenceService.addCargoDoc(b, type: 'invoice', number: 'A', leg: 3), throwsArgumentError);
    });

    testWidgets('the card adds a record and shows the versions', (tester) async {
      final b = (await tester.runAsync(() => booking()))!;
      await tester.pumpWidget(app(CargoDocsCard(booking: b)));
      await settle(tester);
      Future<void> add(String n) async {
        await tester.enterText(find.byKey(const ValueKey('cargoDocNumber')), n);
        await tester.tap(find.byKey(const ValueKey('cargoDocAdd')));
        await settle(tester);
      }

      await add('INV-1');
      expect(find.text('Invoice: INV-1'), findsOneWidget);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await add('INV-2');
      expect(find.text('Invoice: INV-2 · 2 versions'), findsOneWidget);
    });
  });

  group('SAFE4 accident workflow', () {
    test('opens an urgent safety ticket on the booking and tells the customer', () async {
      final b = await booking();
      final id = await TripEvidenceService.reportAccident(b, 'Hit by another truck near Jaipur');
      final t = (await db.collection('tickets').doc(id).get()).data()!;
      expect(t['category'], 'safety');
      expect(t['priority'], 'urgent');
      expect(t['bookingId'], 'b1');
      expect(t['userId'], 'd1');
      uid = 'c1';
      final n = await NotificationService.watchMine().first;
      expect(n.single.type, 'accident_reported');
      uid = 'd1';
      await expectLater(TripEvidenceService.reportAccident(b, 'oops'), throwsA(isA<EvidenceException>()));
    });

    testWidgets('the safety card has an accident button', (tester) async {
      final b = (await tester.runAsync(() => booking()))!;
      await tester.pumpWidget(app(TripSafetyCard(booking: b)));
      await tester.tap(find.byKey(const ValueKey('accidentButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('accidentText')), 'Tyre burst and truck overturned');
      await tester.tap(find.byKey(const ValueKey('accidentSubmit')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('tickets').get()))!.docs, hasLength(1));
    });
  });

  group('N9 payment notifications', () {
    test('marking paid tells the driver, confirming tells the customer', () async {
      await db.collection('bookings').doc('b1').set({
        'driverId': 'd1', 'customerId': 'c1', 'status': 'delivered', 'pickup': 'Delhi', 'drop': 'Jaipur',
        'paymentStatus': 'pending', 'agreedFarePaise': 120000, 'timeline': {},
      });
      uid = 'c1';
      var b = Booking.fromDoc(await db.collection('bookings').doc('b1').get());
      await PaymentService.markPaid(b, 120000);
      uid = 'd1';
      var n = await NotificationService.watchMine().first;
      expect(n.single.type, 'payment_marked');
      expect(n.single.message, 'Delhi → Jaipur: ₹ 1,200');
      b = Booking.fromDoc(await db.collection('bookings').doc('b1').get());
      await PaymentService.confirmReceived(b);
      uid = 'c1';
      n = await NotificationService.watchMine().first;
      expect(n.single.type, 'payment_confirmed');
    });
  });
}
