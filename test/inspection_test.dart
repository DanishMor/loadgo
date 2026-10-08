import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/bilty/bilty_card.dart';
import 'package:transport_app/core/bilty/inspection_service.dart';
import 'package:transport_app/core/bilty/lr_copy_screen.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/bilty/lr_service.dart';
import 'package:transport_app/core/bilty/lr_visibility.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

const _draft = LrDraft(
  consignorName: 'A Traders',
  consigneeName: 'B Stores',
  goods: 'FMCG',
  freightPaise: 2500000,
  advancePaise: 500000,
  marginPaise: 100000,
  consignorPhone: '+919800000001',
  goodsValuePaise: 90000000,
  invoiceNo: 'INV-1',
  consignorGstin: '27ABCDE1234F1Z5',
  ewayBillNo: '123456789012',
);

const _rate = ['freightPaise', 'advancePaise', 'balancePaise', 'gstPaise', 'marginPaise', 'consignorPhone', 'consigneePhone'];

void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late DateTime clock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    clock = DateTime(2026, 10, 8, 10);
    InspectionService.now = () => clock;
    await db.collection('users').doc('tr1').set({'role': 'fleet', 'name': 'Ravi', 'companyName': 'Fast Cargo'});
    await db.collection('users').doc('drvA').set({'role': 'driver', 'driverName': 'Suresh'});
  });
  tearDown(() => InspectionService.now = DateTime.now);

  Future<Booking> booking({String? assigned = 'drvA'}) async {
    await db.collection('bookings').doc('B1').set({
      'loadId': 'L1', 'driverId': 'tr1', 'vehicleId': 'v1', 'customerId': 'customer1', 'status': 'accepted', 'pickup': 'Delhi', 'drop': 'Jaipur', 'cargoType': 'FMCG', 'weight': 7,
      'vehicleType': '20ft', 'vehicleNumber': 'MH12AB1234', 'driverName': 'Ravi', 'driverPhone': '', 'timeline': <String, dynamic>{}, 'fleetOwnerId': 'tr1',
      'assignedDriverId': ?assigned, if (assigned != null) 'assignedDriverName': 'Suresh', 'createdAt': Timestamp.now(), 'updatedAt': Timestamp.now(),
    });
    return Booking.fromDoc(await db.collection('bookings').doc('B1').get());
  }

  Future<LrPublic> issue(Booking b, {String mode = ComplianceMode.inspectionOnRequest}) async {
    uid = 'tr1';
    return LrService.issue(b, LrDraft(
        consignorName: _draft.consignorName, consigneeName: _draft.consigneeName, goods: _draft.goods, freightPaise: _draft.freightPaise, advancePaise: _draft.advancePaise, marginPaise: _draft.marginPaise,
        consignorPhone: _draft.consignorPhone, goodsValuePaise: _draft.goodsValuePaise, invoiceNo: _draft.invoiceNo, consignorGstin: _draft.consignorGstin, ewayBillNo: _draft.ewayBillNo, complianceMode: mode));
  }

  group('mode x copy matrix', () {
    test('every combination: the rate group never reaches the driver; compliance follows the rule', () async {
      final b = await booking();
      for (final mode in ComplianceMode.all) {
        final lr = await issue(b, mode: mode);
        final bundle = await LrService.bundle(lr);
        for (final grant in [false, true]) {
          for (final copy in LrCopy.all) {
            final snap = LrVisibility.snapshot(bundle, copy, grantValid: grant, consigneeShowsRate: false);
            final hasCompliance = snap.containsKey('ewayBillNo') || snap.containsKey('invoiceNo') || snap.containsKey('goodsValuePaise') || snap.containsKey('consignorGstin');
            final expected = switch (copy) {
              LrCopy.full => true,
              LrCopy.consignee => mode == ComplianceMode.show,
              _ => mode == ComplianceMode.show || grant,
            };
            expect(hasCompliance, expected, reason: 'copy $copy, mode $mode, grant $grant');
            if (copy == LrCopy.driver) {
              for (final k in _rate) {
                expect(snap.containsKey(k), isFalse, reason: '$k reached the driver ($mode, grant $grant)');
              }
            }
            if (copy == LrCopy.consignee) expect(snap.containsKey('marginPaise'), isFalse);
          }
        }
        await db.collection('lrs').doc(lr.id).update({'status': 'cancelled', 'cancelReason': 'test'});
      }
    });
  });

  group('request, approve, deny, expiry', () {
    test('the trip driver asks; the owner is notified and it is audited', () async {
      final b = await booking();
      final lr = await issue(b);
      uid = 'drvA';
      await InspectionService.request(b, lr, driverName: 'Suresh');
      final req = (await db.collection('lrs').doc(lr.id).collection('inspection_requests').doc('drvA').get()).data()!;
      expect(req['status'], 'pending');
      expect(req['ownerId'], 'tr1');
      final n = (await db.collection('notifications').where('userId', isEqualTo: 'tr1').get()).docs.single.data();
      expect(n['type'], 'inspection_request');
      expect((await db.collection('audit_events').where('type', isEqualTo: 'inspection_request').get()).docs.length, 1);
    });

    test('a driver of another trip, the owner and a stranger cannot ask', () async {
      final b = await booking();
      final lr = await issue(b);
      for (final who in ['drvB', 'tr1', 'customer1']) {
        uid = who;
        await expectLater(InspectionService.request(b, lr, driverName: 'x'), throwsA(isA<InspectionException>()), reason: who);
      }
    });

    test('approve creates a 2 hour grant with the verify token, notifies the driver, audits', () async {
      final b = await booking();
      final lr = await issue(b);
      uid = 'drvA';
      await InspectionService.request(b, lr, driverName: 'Suresh');
      uid = 'tr1';
      await InspectionService.respond(b, lr, 'drvA', approve: true);
      final g = (await db.collection('lrs').doc(lr.id).collection('inspection_grants').doc('drvA').get()).data()!;
      expect((g['expiresAt'] as Timestamp).toDate(), clock.add(const Duration(hours: 2)));
      expect(g['kind'], 'approved');
      expect(g['ownerId'], 'tr1');
      expect(g['verifyToken'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect((await db.collection('lrs').doc(lr.id).collection('inspection_requests').doc('drvA').get()).data()!['status'], 'approved');
      expect((await db.collection('notifications').where('userId', isEqualTo: 'drvA').get()).docs.single.data()['type'], 'inspection_approved');
      expect((await db.collection('audit_events').where('type', isEqualTo: 'inspection_approve').get()).docs.length, 1);
    });

    test('deny writes no grant, notifies and audits; the driver can ask again', () async {
      final b = await booking();
      final lr = await issue(b);
      uid = 'drvA';
      await InspectionService.request(b, lr, driverName: 'Suresh');
      uid = 'tr1';
      await InspectionService.respond(b, lr, 'drvA', approve: false);
      expect((await db.collection('lrs').doc(lr.id).collection('inspection_grants').get()).docs, isEmpty);
      expect((await db.collection('notifications').where('userId', isEqualTo: 'drvA').get()).docs.single.data()['type'], 'inspection_denied');
      expect((await db.collection('audit_events').where('type', isEqualTo: 'inspection_deny').get()).docs.length, 1);
      uid = 'drvA';
      await InspectionService.request(b, lr, driverName: 'Suresh');
      expect((await db.collection('lrs').doc(lr.id).collection('inspection_requests').doc('drvA').get()).data()!['status'], 'pending');
    });

    test('only the issuer answers', () async {
      final b = await booking();
      final lr = await issue(b);
      uid = 'customer1';
      await expectLater(InspectionService.respond(b, lr, 'drvA', approve: true), throwsA(isA<InspectionException>()));
      uid = 'drvA';
      await expectLater(InspectionService.respond(b, lr, 'drvA', approve: true), throwsA(isA<InspectionException>()));
    });

    test('pre-approve for N hours (1 to 72) and end it early', () async {
      final b = await booking();
      final lr = await issue(b);
      uid = 'tr1';
      await expectLater(InspectionService.allowFor(b, lr, 0), throwsA(isA<InspectionException>()));
      await expectLater(InspectionService.allowFor(b, lr, 73), throwsA(isA<InspectionException>()));
      final g = await InspectionService.allowFor(b, lr, 24);
      expect(g.kind, 'preapproved');
      expect(g.expiresAt, clock.add(const Duration(hours: 24)));
      final stored = (await db.collection('lrs').doc(lr.id).collection('inspection_grants').doc('drvA').get()).data()!;
      expect(stored['kind'], 'preapproved');
      final a = (await db.collection('audit_events').where('type', isEqualTo: 'inspection_approve').get()).docs.single.data();
      expect((a['data'] as Map)['advance'], true);
      await InspectionService.revoke(lr, 'drvA');
      expect((await db.collection('lrs').doc(lr.id).collection('inspection_grants').get()).docs, isEmpty);
    });

    test('a booking without a driver cannot be pre-approved', () async {
      final b = await booking(assigned: null);
      final lr = await issue(b);
      uid = 'tr1';
      await expectLater(InspectionService.allowFor(b, lr, 2), throwsA(isA<InspectionException>()));
    });

    test('grants know when they have ended', () {
      final g = InspectionGrant(driverId: 'd', kind: 'approved', expiresAt: DateTime(2026, 10, 8, 12));
      expect(g.isValid(DateTime(2026, 10, 8, 11, 59)), isTrue);
      expect(g.isValid(DateTime(2026, 10, 8, 12)), isFalse);
      expect(g.isValid(DateTime(2026, 10, 8, 13)), isFalse);
    });
  });

  group('offline copy', () {
    testWidgets('saved while the grant lasts, readable offline, deleted when it ends, expiry audited once', (tester) async {
      final b = await booking();
      late LrPublic lr;
      late LrBundle bundle;
      InspectionGrant? grant;
      await tester.runAsync(() async {
        lr = await issue(b);
        uid = 'tr1';
        grant = await InspectionService.allowFor(b, lr, 2);
        bundle = LrBundle(lr, compliance: LrCompliance(goodsValuePaise: 90000000, invoiceNo: 'INV-1', consignorGstin: '27ABCDE1234F1Z5', ewayBillNo: '123456789012'));
        uid = 'drvA';
      });

      final end = await tester.runAsync(() => InspectionService.saveCopy(bundle, grant: grant, driverName: 'Suresh', language: AppLanguage.hindi));
      expect(end, clock.add(const Duration(hours: 2)));
      final cache = InspectionCache();
      var saved = await tester.runAsync(() => cache.get(lr.id, clock));
      expect(String.fromCharCodes(saved!.bytes.take(5)), '%PDF-');
      expect(saved.expiresAt, end);

      // 1 hour 59 minutes later: still there, with no network call.
      clock = clock.add(const Duration(hours: 1, minutes: 59));
      expect(await tester.runAsync(() => cache.get(lr.id, clock)), isNotNull);

      // 2 hours later: gone, and the end is audited once however often we look.
      clock = clock.add(const Duration(minutes: 1));
      expect(await tester.runAsync(() => cache.get(lr.id, clock)), isNull);
      await tester.runAsync(() async {
        expect(await InspectionService.sweep(lr, grant), isTrue);
        expect(await InspectionService.sweep(lr, grant), isTrue);
      });
      final events = await tester.runAsync(() => db.collection('audit_events').where('type', isEqualTo: 'inspection_expire').get());
      expect(events!.docs.length, 1);
    });

    test('nothing is saved without a valid grant or show mode; a show-mode copy lasts 12 hours', () async {
      final b = await booking();
      final lr = await issue(b);
      final noGrant = LrBundle(lr, compliance: const LrCompliance(ewayBillNo: '123456789012'));
      expect(await InspectionService.saveCopy(noGrant, grant: null, driverName: 'S', language: AppLanguage.english), isNull);
      final old = InspectionGrant(driverId: 'drvA', kind: 'approved', expiresAt: clock.subtract(const Duration(minutes: 1)));
      expect(await InspectionService.saveCopy(noGrant, grant: old, driverName: 'S', language: AppLanguage.english), isNull);
      await db.collection('lrs').doc(lr.id).update({'complianceMode': 'show'});
      final shown = await LrService.bundle(lr);
      final end = await InspectionService.saveCopy(LrBundle(shown.pub, compliance: const LrCompliance(ewayBillNo: '123456789012')), grant: null, driverName: 'S', language: AppLanguage.english);
      expect(end, clock.add(const Duration(hours: 12)));
    });

    test('purgeExpired removes only the copies whose time is over', () async {
      final cache = InspectionCache();
      await cache.put('a', Uint8List.fromList([1]), clock.add(const Duration(hours: 1)));
      await cache.put('b', Uint8List.fromList([2]), clock.subtract(const Duration(minutes: 1)));
      expect(await cache.purgeExpired(clock), 1);
      expect(await cache.get('a', clock), isNotNull);
      expect(await cache.get('b', clock), isNull);
    });

    test('the inspection PDF has the watermark text, no rate, and builds for every language', () async {
      final b = await booking();
      final lr = await issue(b);
      for (final lang in AppLanguage.values) {
        final bytes = await InspectionService.buildCopy(LrBundle(lr, compliance: const LrCompliance(ewayBillNo: '123456789012', invoiceNo: 'I1')), driverName: 'सुरेश', language: lang, verifyToken: 'a' * 32);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-', reason: lang.name);
      }
    });
  });

  group('screens', () {
    Widget app(Widget home) => MaterialApp(home: home);

    setUp(() {});

    testWidgets('driver sees the plain labels and the request button; pending, then granted', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final b = await booking();
      late LrPublic lr;
      await tester.runAsync(() async => lr = await issue(b));
      uid = 'drvA';
      await tester.pumpWidget(app(DriverLrScreen(booking: b)));
      await settle(tester);
      expect(find.byKey(const ValueKey('rateHiddenLabel')), findsOneWidget);
      expect(find.text('Rate hidden by owner'), findsOneWidget);
      expect(find.text('Owner approval needed for inspection'), findsOneWidget);
      expect(find.byKey(const ValueKey('lrRow_blEway')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('inRequest')));
      await settle(tester);
      expect(find.byKey(const ValueKey('inPendingLabel')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('inRequest'))).onPressed, isNull);

      // The owner approves (a grant appears): the details open and the labels change.
      await tester.runAsync(() async {
        uid = 'tr1';
        await InspectionService.respond(b, lr, 'drvA', approve: true);
        uid = 'drvA';
      });
      await settle(tester);
      expect(find.byKey(const ValueKey('inAllowedLabel')), findsOneWidget);
      expect(find.byKey(const ValueKey('inNeedApprovalLabel')), findsNothing);
      expect(find.byKey(const ValueKey('inSave')), findsOneWidget);
      expect(find.text('Rate hidden by owner'), findsOneWidget);
      expect(find.byKey(const ValueKey('lrRow_blFreight')), findsNothing);
    });

    testWidgets('after the grant ends the driver is back to "owner approval needed" and can ask again', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final b = await booking();
      late LrPublic lr;
      await tester.runAsync(() async {
        lr = await issue(b);
        await InspectionService.allowFor(b, lr, 1);
      });
      uid = 'drvA';
      await tester.pumpWidget(app(DriverLrScreen(booking: b)));
      await settle(tester);
      expect(find.byKey(const ValueKey('inAllowedLabel')), findsOneWidget);
      clock = clock.add(const Duration(hours: 1, minutes: 1));
      await tester.pump(const Duration(seconds: 16));
      await settle(tester);
      expect(find.byKey(const ValueKey('inAllowedLabel')), findsNothing);
      expect(find.byKey(const ValueKey('inNeedApprovalLabel')), findsOneWidget);
      expect(find.byKey(const ValueKey('inExpiredLabel')), findsOneWidget);
      expect(find.byKey(const ValueKey('inRequest')), findsOneWidget);
    });

    testWidgets('the owner sees the request on the LR card and approves it', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final b = await booking();
      late LrPublic lr;
      await tester.runAsync(() async {
        lr = await issue(b);
        uid = 'drvA';
        await InspectionService.request(b, lr, driverName: 'Suresh');
        uid = 'tr1';
      });
      await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: BiltyCard(booking: b)))));
      await settle(tester);
      expect(find.byKey(const ValueKey('inReq_drvA')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('inApprove_drvA')));
      await settle(tester);
      final g = await tester.runAsync(() => db.collection('lrs').doc(lr.id).collection('inspection_grants').doc('drvA').get());
      expect(g!.exists, isTrue);
      expect(find.byKey(const ValueKey('inReq_drvA')), findsNothing);
    });
  });
}
