import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/bilty/bilty_card.dart';
import 'package:transport_app/core/bilty/lr_copy_screen.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/bilty/lr_pdf.dart';
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
  packages: 40,
  weightTons: 7.5,
  freightPaise: 2500000,
  advancePaise: 500000,
  marginPaise: 100000,
  gstPaise: 125000,
  consignorPhone: '+919800000001',
  consigneePhone: '+919800000002',
  goodsValuePaise: 90000000,
  invoiceNo: 'INV-1',
  consignorGstin: '27ABCDE1234F1Z5',
  consigneeGstin: '08ABCDE1234F1Z5',
  ewayBillNo: '123456789012',
);

const _rate = ['freightPaise', 'advancePaise', 'balancePaise', 'gstPaise', 'marginPaise'];
const _phones = ['consignorPhone', 'consigneePhone'];

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    await db.collection('users').doc('tr1').set({'role': 'fleet', 'name': 'Ravi', 'companyName': 'Fast Cargo'});
    await db.collection('users').doc('customer1').set({'role': 'customer', 'name': 'Anil'});
  });

  Future<Booking> booking(String id, {String customer = 'customer1', String? fleet = 'tr1', String? assigned = 'drvA', String driver = 'tr1', String status = 'accepted'}) async {
    await db.collection('bookings').doc(id).set({
      'loadId': 'L$id', 'driverId': driver, 'vehicleId': 'v1', 'customerId': customer, 'status': status,
      'pickup': 'Delhi', 'drop': 'Jaipur', 'cargoType': 'FMCG', 'weight': 7, 'vehicleType': '20ft',
      'vehicleNumber': 'MH12AB1234', 'driverName': 'Ravi', 'driverPhone': '', 'timeline': <String, dynamic>{},
      'fleetOwnerId': ?fleet, 'assignedDriverId': ?assigned, if (assigned != null) 'assignedDriverName': 'Suresh',
      'createdAt': Timestamp.now(), 'updatedAt': Timestamp.now(),
    });
    return Booking.fromDoc(await db.collection('bookings').doc(id).get());
  }

  group('visibility matrix', () {
    test('the driver copy never has a rate, margin or phone, whatever the mode or grant', () {
      for (final mode in ComplianceMode.all) {
        for (final grant in [false, true]) {
          for (final showRate in [false, true]) {
            final f = LrVisibility.fields(LrCopy.driver, consigneeShowsRate: showRate, complianceMode: mode, grantValid: grant);
            for (final k in [..._rate, ..._phones]) {
              expect(f.contains(k), isFalse, reason: '$k in driver copy ($mode, grant $grant)');
            }
          }
        }
      }
      expect(LrVisibility.driverMaySeeRate(), isFalse);
    });

    test('the consignee copy never has margin or phone; the rate only when the owner says so', () {
      for (final mode in ComplianceMode.all) {
        final off = LrVisibility.fields(LrCopy.consignee, complianceMode: mode);
        final on = LrVisibility.fields(LrCopy.consignee, consigneeShowsRate: true, complianceMode: mode);
        for (final k in ['marginPaise', ..._phones]) {
          expect(off.contains(k) || on.contains(k), isFalse);
        }
        for (final k in LrFields.rateKeys) {
          expect(off.contains(k), isFalse);
          expect(on.contains(k), isTrue);
        }
      }
    });

    test('the full copy has everything', () {
      final f = LrVisibility.fields(LrCopy.full);
      for (final k in [...LrFields.publicKeys, ..._rate, ..._phones, ...LrFields.complianceKeys]) {
        expect(f.contains(k), isTrue, reason: k);
      }
    });

    test('compliance reaches the driver only in show mode or with a valid grant', () {
      expect(LrVisibility.showsCompliance(LrCopy.driver), isFalse);
      expect(LrVisibility.showsCompliance(LrCopy.driver, complianceMode: ComplianceMode.inspectionOnRequest), isFalse);
      expect(LrVisibility.showsCompliance(LrCopy.driver, complianceMode: ComplianceMode.show), isTrue);
      expect(LrVisibility.showsCompliance(LrCopy.driver, complianceMode: ComplianceMode.inspectionOnRequest, grantValid: true), isTrue);
      expect(LrVisibility.showsCompliance(LrCopy.driver, complianceMode: ComplianceMode.hide, grantValid: true), isTrue);
    });

    test('who may issue: transporter and customer of the booking only', () {
      bool can({bool c = false, bool t = false, bool d = false, bool a = false}) =>
          LrVisibility.canIssue(isCustomerOfBooking: c, isTransporterOfBooking: t, isDriver: d, isAdmin: a);
      expect(can(c: true), isTrue);
      expect(can(t: true), isTrue);
      expect(can(d: true), isFalse);
      expect(can(a: true), isFalse);
      expect(can(c: true, a: true), isFalse);
      expect(can(), isFalse);
    });

    test('verify snapshot holds only LR no, route, status and issuer', () {
      const p = LrPublic(id: 'x', bookingId: 'b', issuerId: 'tr1', issuerRole: 'transporter', customerId: 'c', lrNo: 'TR-2026-000001', seq: 1, year: 2026, version: 1, status: 'issued', pickup: 'Delhi', drop: 'Jaipur', issuerName: 'Fast Cargo', goods: 'Steel', weightTons: 9);
      final v = LrVisibility.verifySnapshot(p);
      expect(v.keys.toSet(), {'lrNo', 'route', 'status', 'issuerName'});
      expect(v['route'], 'Delhi → Jaipur');
    });
  });

  group('numbers and drafts', () {
    test('LR number is prefix + year + 6 digits; ids carry issuer, year, seq and version', () {
      expect(lrNumber(LrIssuerRole.transporter, 2026, 12), 'TR-2026-000012');
      expect(lrNumber(LrIssuerRole.customer, 2026, 1), 'CS-2026-000001');
      expect(lrDocId('tr1', 2026, 3, 2), 'tr1_2026_3_v2');
    });

    test('draft checks: names, advance, GSTIN, e-way bill', () {
      expect(() => _draft.validate(), returnsNormally);
      LrDraft with_({String? c, int? adv, String? g, String? e}) => LrDraft(
          consignorName: c ?? 'A', consigneeName: 'B', goods: 'G', freightPaise: 1000, advancePaise: adv ?? 0, consignorGstin: g ?? '', ewayBillNo: e ?? '');
      String reason(LrDraft d) {
        try {
          d.validate();
        } on LrException catch (e) {
          return e.reason;
        }
        return 'ok';
      }

      expect(reason(with_(c: ' ')), 'fields');
      expect(reason(with_(adv: 2000)), 'advance');
      expect(reason(with_(g: 'BAD')), 'gstin');
      expect(reason(with_(e: '123')), 'eway');
      expect(_draft.balancePaise, 2000000);
    });

    test('share link ends 2 days after delivery; before delivery it allows for the trip', () async {
      final b = await booking('B1');
      final now = DateTime(2026, 10, 8, 10);
      expect(LrService.defaultExpiry(b, now), now.add(const Duration(days: 5)));
      final done = await booking('B2', status: 'delivered');
      final delivered = Booking.fromDoc(await (db.collection('bookings').doc('B2')..update({'timeline.delivered': Timestamp.fromDate(DateTime(2026, 10, 9))})).get());
      expect(LrService.defaultExpiry(delivered, now), DateTime(2026, 10, 11));
      expect(done.id, 'B2');
    });

    test('tokens are 128 bits of hex and differ', () {
      final a = LrService.newToken(), b = LrService.newToken();
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a, isNot(b));
    });
  });

  group('service', () {
    test('transporter and customer issue, a driver and a stranger cannot; numbers count per issuer', () async {
      final b = await booking('B1');
      uid = 'tr1';
      final first = await LrService.issue(b, _draft);
      final second = await LrService.issue(b, _draft);
      expect(first.lrNo, 'TR-${DateTime.now().year}-000001');
      expect(second.lrNo, 'TR-${DateTime.now().year}-000002');
      uid = 'customer1';
      final slip = await LrService.issue(b, _draft);
      expect(slip.lrNo, startsWith('CS-'));
      expect(slip.seq, 1, reason: 'each issuer has their own series');
      for (final who in ['drvA', 'admin1', 'stranger']) {
        uid = who;
        await expectLater(LrService.issue(b, _draft), throwsA(isA<LrException>()), reason: who);
      }
      uid = 'customer1';
      final other = await booking('B9', customer: 'customer2');
      await expectLater(LrService.issue(other, _draft), throwsA(isA<LrException>()));
      final audits = await db.collection('audit_events').where('type', isEqualTo: 'lr_issue').get();
      expect(audits.docs.length, 3);
    });

    test('private parts are stored apart from the public part', () async {
      final b = await booking('B1');
      uid = 'tr1';
      final lr = await LrService.issue(b, _draft);
      final pub = (await db.collection('lrs').doc(lr.id).get()).data()!;
      for (final k in [..._rate, ..._phones, 'goodsValuePaise', 'invoiceNo', 'ewayBillNo']) {
        expect(pub.containsKey(k), isFalse, reason: '$k must not be on the public document');
      }
      final details = (await db.collection('lrs').doc(lr.id).collection('private').doc('details').get()).data()!;
      expect(details['freightPaise'], 2500000);
      expect(details['balancePaise'], 2000000);
      expect(details['freightPaise'], isA<int>());
      final comp = (await db.collection('lrs').doc(lr.id).collection('private').doc('compliance').get()).data()!;
      expect(comp['ewayBillNo'], '123456789012');
    });

    test('edit makes a new version with the same number; the old one is superseded', () async {
      final b = await booking('B1');
      uid = 'tr1';
      final v1 = await LrService.issue(b, _draft);
      final v2 = await LrService.newVersion(b, v1, _draft);
      expect(v2.lrNo, v1.lrNo);
      expect(v2.version, 2);
      final all = await LrService.watchForBooking('B1').first;
      expect(all.map((l) => '${l.version}:${l.status}'), ['2:issued', '1:superseded']);
      expect(LrService.current(all)!.version, 2);
      await expectLater(LrService.newVersion(b, v1, _draft), throwsA(isA<LrException>()), reason: 'the old version is view only');
      await expectLater(LrService.cancel(v1, 'wrong'), throwsA(isA<LrException>()));
      expect((await db.collection('audit_events').where('type', isEqualTo: 'lr_version').get()).docs.length, 1);
    });

    test('cancel needs a reason and the issuer; it is audited', () async {
      final b = await booking('B1');
      uid = 'tr1';
      final lr = await LrService.issue(b, _draft);
      await expectLater(LrService.cancel(lr, 'no'), throwsA(isA<LrException>()));
      uid = 'customer1';
      await expectLater(LrService.cancel(lr, 'not mine to cancel'), throwsA(isA<LrException>()));
      uid = 'tr1';
      await LrService.cancel(lr, 'wrong vehicle');
      final now = (await LrService.watchForBooking('B1').first).single;
      expect(now.status, LrStatus.cancelled);
      expect(now.cancelReason, 'wrong vehicle');
      final a = (await db.collection('audit_events').where('type', isEqualTo: 'lr_cancel').get()).docs.single.data();
      expect((a['data'] as Map)['reason'], 'wrong vehicle');
    });

    test('compliance mode changes are audited and do not make a version', () async {
      final b = await booking('B1');
      uid = 'tr1';
      final lr = await LrService.issue(b, _draft);
      expect(lr.complianceMode, ComplianceMode.hide);
      await LrService.setComplianceMode(lr, ComplianceMode.inspectionOnRequest);
      final all = await LrService.watchForBooking('B1').first;
      expect(all.length, 1);
      expect(all.single.complianceMode, ComplianceMode.inspectionOnRequest);
      final a = (await db.collection('audit_events').where('type', isEqualTo: 'lr_mode').get()).docs.single.data();
      expect((a['data'] as Map)['from'], 'hide');
      expect((a['data'] as Map)['to'], 'inspection_on_request');
    });

    test('driver copy snapshot has no rate; sending to the driver notifies the assigned driver', () async {
      final b = await booking('B1');
      uid = 'tr1';
      final lr = await LrService.issue(b, _draft);
      final bundle = await LrService.bundle(lr);
      final snap = LrVisibility.snapshot(bundle, LrCopy.driver);
      for (final k in [..._rate, ..._phones, ...LrFields.complianceKeys]) {
        expect(snap.containsKey(k), isFalse, reason: k);
      }
      expect(snap['lrNo'], lr.lrNo);
      expect(snap['driverName'], 'Suresh');
      await LrService.sendToDriver(b, lr);
      final n = (await db.collection('notifications').where('userId', isEqualTo: 'drvA').get()).docs.single.data();
      expect(n['type'], 'lr_sent');
    });

    test('share links: snapshot of that copy only, revoke, verify link reused', () async {
      final b = await booking('B1');
      uid = 'tr1';
      final lr = await LrService.issue(b, _draft);
      final bundle = await LrService.bundle(lr);
      final token = await LrService.createShare(b, lr, LrCopy.consignee, LrVisibility.snapshot(bundle, LrCopy.consignee));
      final doc = (await db.collection('lr_shares').doc(token).get()).data()!;
      expect(doc['copyType'], 'consignee');
      expect((doc['fields'] as Map).containsKey('freightPaise'), isFalse);
      expect((doc['fields'] as Map).containsKey('marginPaise'), isFalse);
      expect(doc['revoked'], false);
      expect(doc['views'], 0);
      final shares = await LrService.watchShares(lr.id).first;
      expect(shares.single.isLive(DateTime.now()), isTrue);
      await LrService.revokeShare(shares.single, lr);
      expect((await db.collection('lr_shares').doc(token).get()).data()!['revoked'], true);
      final v1 = await LrService.verifyToken(b, lr);
      final v2 = await LrService.verifyToken(b, lr);
      expect(v1, v2);
      expect(((await db.collection('lr_shares').doc(v1).get()).data()!['fields'] as Map).keys.toSet(), {'lrNo', 'route', 'status', 'issuerName'});
      await LrService.cancel(lr, 'duplicate');
      expect((await db.collection('lr_shares').doc(v1).get()).data()!['status'], 'cancelled');
    });
  });

  group('pdf', () {
    testWidgets('builds for every language with bundled fonts and a QR code', (tester) async {
      final b = await booking('B1');
      uid = 'tr1';
      late LrBundle bundle;
      await tester.runAsync(() async {
        final lr = await LrService.issue(b, _draft);
        bundle = await LrService.bundle(lr);
      });
      for (final lang in AppLanguage.values) {
        final bytes = await tester.runAsync(() => buildLrPdf(LrPdfInput(
              fields: LrVisibility.snapshot(bundle, LrCopy.full),
              copy: LrCopy.full,
              issuerRole: LrIssuerRole.transporter,
              language: lang,
              verifyUrl: LrService.linkFor('a' * 32),
              issuerName: 'फास्ट कार्गो',
              delivered: false,
              generatedAt: DateTime(2026, 10, 8, 9, 30),
            )));
        expect(String.fromCharCodes(bytes!.take(5)), '%PDF-', reason: lang.name);
        expect(bytes.length, greaterThan(5000), reason: lang.name);
      }
    });

    test('every bundled font file is in the assets folder and listed', () {
      expect(LrFonts.files.length, 9);
    });
  });

  group('screens', () {
    Widget app(Widget home) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: home)));

    testWidgets('transporter sees Create; the trip driver sees only the driver copy button', (tester) async {
      final b = await booking('B1');
      uid = 'tr1';
      await tester.runAsync(() => LrService.issue(b, _draft));
      await tester.pumpWidget(app(BiltyCard(booking: b)));
      await settle(tester);
      expect(find.byKey(const ValueKey('biltyNo')), findsOneWidget);
      expect(find.byKey(const ValueKey('biltySend')), findsOneWidget);
      expect(find.byKey(const ValueKey('biltyEdit')), findsOneWidget);
      expect(find.byKey(const ValueKey('biltyModePicker')), findsOneWidget);

      uid = 'drvA';
      await tester.pumpWidget(app(BiltyCard(key: UniqueKey(), booking: b)));
      await settle(tester);
      expect(find.byKey(const ValueKey('biltyDriverCopy')), findsOneWidget);
      expect(find.byKey(const ValueKey('biltySend')), findsNothing);
      expect(find.byKey(const ValueKey('biltyEdit')), findsNothing);
      expect(find.byKey(const ValueKey('biltyCancel')), findsNothing);
      expect(find.byKey(const ValueKey('biltyModePicker')), findsNothing);

      uid = 'stranger';
      await tester.pumpWidget(app(BiltyCard(key: UniqueKey(), booking: b)));
      await settle(tester);
      expect(find.byKey(const ValueKey('biltyNo')), findsNothing);
      expect(find.byKey(const ValueKey('biltyCreate')), findsNothing);
    });

    testWidgets('driver copy screen shows the route and "Rate hidden by owner", no rate rows', (tester) async {
      final b = await booking('B1');
      uid = 'tr1';
      await tester.runAsync(() => LrService.issue(b, _draft));
      uid = 'drvA';
      await tester.pumpWidget(MaterialApp(home: DriverLrScreen(booking: b)));
      await settle(tester);
      expect(find.text('Rate hidden by owner'), findsOneWidget);
      expect(find.text('Delhi → Jaipur'), findsOneWidget);
      for (final k in ['blFreight', 'blAdvance', 'blBalance', 'blMargin', 'blConsignorPhone', 'blEway']) {
        expect(find.byKey(ValueKey('lrRow_$k')), findsNothing, reason: k);
      }
    });

    testWidgets('customer without an LR can create a booking slip', (tester) async {
      final b = await booking('B1');
      uid = 'customer1';
      await tester.pumpWidget(app(BiltyCard(booking: b)));
      await settle(tester);
      expect(find.byKey(const ValueKey('biltyCreate')), findsOneWidget);
    });
  });
}
