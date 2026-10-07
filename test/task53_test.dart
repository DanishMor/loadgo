import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_demo_screen.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/demo/demo_seed.dart';
import 'package:transport_app/core/l10n/demo_strings.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/demo_service.dart';

import 'test_utils.dart';

Widget host(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: child));

void main() {
  late FakeFirebaseFirestore db;
  final now = DateTime(2026, 10, 7, 10);

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    DemoService.release = false;
  });

  group('DemoSeed', () {
    final docs = DemoSeed.build(now: now);

    test('default set: 3 customers, 3 drivers, 3 vehicles, 6 loads, 3 bookings', () {
      int n(String c) => docs.where((d) => d.collection == c).length;
      expect([n('users'), n('vehicles'), n('loads'), n('bookings')], [6, 3, 6, 3]);
    });

    test('every document is flagged demo and has a demo_ id', () {
      for (final d in docs) {
        expect(d.data['demo'], isTrue, reason: d.id);
        expect(d.id, startsWith(DemoSeed.idPrefix));
        expect(DemoSeed.collections, contains(d.collection));
      }
      expect(docs.map((d) => '${d.collection}/${d.id}').toSet().length, docs.length, reason: 'ids are unique');
    });

    test('deterministic for the same time', () {
      final a = DemoSeed.build(now: now).map((d) => '${d.collection}/${d.id}/${d.data['status']}').toList();
      expect(DemoSeed.build(now: now).map((d) => '${d.collection}/${d.id}/${d.data['status']}').toList(), a);
    });

    test('references line up: bookings point at demo loads, drivers, vehicles and customers', () {
      final ids = {for (final d in docs) '${d.collection}/${d.id}'};
      for (final b in docs.where((d) => d.collection == 'bookings')) {
        expect(ids, contains('loads/${b.data['loadId']}'));
        expect(ids, contains('users/${b.data['driverId']}'));
        expect(ids, contains('users/${b.data['customerId']}'));
        expect(ids, contains('vehicles/${b.data['vehicleId']}'));
        expect(b.data['status'], 'delivered');
        expect(b.data['agreedFarePaise'], isA<int>());
      }
      final open = docs.where((d) => d.collection == 'loads' && d.data['status'] == 'open').length;
      expect(open, 3);
    });

    test('demo phones are not real numbers', () {
      for (final u in docs.where((d) => d.collection == 'users')) {
        expect(u.data['phone'] as String, startsWith('+91000000'));
      }
    });

    test('counts are respected; no customers means no loads; bookings capped by loads', () {
      expect(DemoSeed.build(customers: 0, now: now).where((d) => d.collection == 'loads'), isEmpty);
      expect(DemoSeed.build(drivers: 0, now: now).where((d) => d.collection == 'bookings'), isEmpty);
      expect(DemoSeed.build(loads: 2, bookings: 9, now: now).where((d) => d.collection == 'bookings').length, 2);
      expect(DemoSeed.build(customers: 0, drivers: 0, loads: 0, bookings: 0, now: now), isEmpty);
    });

    test('the app models read the documents', () async {
      for (final d in docs) {
        await db.collection(d.collection).doc(d.id).set(d.data);
      }
      final load = Load.fromDoc(await db.collection('loads').doc('demo_l0').get());
      expect((load.pickup, load.drop, load.status), ('Delhi', 'Jaipur', 'closed'));
      final open = Load.fromDoc(await db.collection('loads').doc('demo_l4').get());
      expect(open.status, 'open');
      expect(Vehicle.fromDoc(await db.collection('vehicles').doc('demo_v0').get()).number, 'DEMO1000');
      expect(Booking.fromDoc(await db.collection('bookings').doc('demo_b1').get()).status, 'delivered');
    });
  });

  group('DemoGuard', () {
    test('release needs allowDemo, other builds are free', () {
      expect(DemoGuard.allowed(release: false, allowDemo: false), isTrue);
      expect(DemoGuard.allowed(release: true, allowDemo: false), isFalse);
      expect(DemoGuard.allowed(release: true, allowDemo: true), isTrue);
    });
  });

  group('DemoService', () {
    test('create writes everything, count sees it, removeAll deletes only demo documents', () async {
      await db.collection('users').doc('real1').set({'name': 'Real'});
      await db.collection('loads').doc('L1').set({'status': 'open'});
      await db.collection('users').doc('real2').set({'name': 'Flagged but real id', 'demo': true});
      expect(await DemoService.create(now: now), 18);
      expect(await DemoService.count(), 18);
      expect(await DemoService.removeAll(), 18);
      expect(await DemoService.count(), 0);
      expect((await db.collection('users').doc('real1').get()).exists, isTrue);
      expect((await db.collection('loads').doc('L1').get()).exists, isTrue);
      expect((await db.collection('users').doc('real2').get()).exists, isTrue, reason: 'no demo_ prefix, so it stays');
    });

    test('create twice overwrites the same ids', () async {
      await DemoService.create(now: now);
      await DemoService.create(now: now);
      expect(await DemoService.count(), 18);
    });

    test('release build: blocked unless config/app.allowDemo; removal always works', () async {
      DemoService.release = true;
      expect(DemoService.create(now: now), throwsA(isA<DemoBlockedException>()));
      expect((await db.collection('users').get()).docs, isEmpty);
      await db.collection('config').doc('app').set({'allowDemo': true});
      expect(await DemoService.create(now: now), 18);
      await db.collection('config').doc('app').set({'allowDemo': false});
      expect(await DemoService.removeAll(), 18);
    });

    test('removeAll handles more than one batch', () async {
      for (var i = 0; i < 450; i++) {
        await db.collection('loads').doc('demo_x$i').set({'demo': true});
      }
      expect(await DemoService.removeAll(), 450);
      expect((await db.collection('loads').get()).docs, isEmpty);
    });
  });

  group('AdminDemoScreen', () {
    testWidgets('create and remove with confirmation', (t) async {
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(const AdminDemoScreen()));
      await settle(t);
      expect(find.text('0 demo documents'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('demoCreate')));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('0 demo documents'), findsOneWidget, reason: 'cancelled');
      await t.tap(find.byKey(const ValueKey('demoCreate')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('demoConfirm')));
      await settle(t);
      expect(find.text('Created 18 documents'), findsOneWidget);
      expect(find.text('18 demo documents'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await t.tap(find.byKey(const ValueKey('demoRemove')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('demoConfirm')));
      await settle(t);
      expect(find.text('0 demo documents'), findsOneWidget);
    });

    testWidgets('release without allowDemo shows the blocked message', (t) async {
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      DemoService.release = true;
      await t.pumpWidget(host(const AdminDemoScreen()));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('demoCreate')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('demoConfirm')));
      await settle(t);
      expect(find.textContaining('Demo data is off in this build'), findsOneWidget);
    });
  });

  test('staff area: demo data is super admin only', () {
    expect(staffCan('super', 'adminDemo'), isTrue);
    for (final r in ['support', 'ops', 'verifier']) {
      expect(staffCan(r, 'adminDemo'), isFalse);
    }
  });

  test('demo strings: 12 languages, same placeholders', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in demoStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
      for (var i = 1; i < 12; i++) {
        expect(ph.allMatches(e.value[i]).map((m) => m[1]).toSet(), want, reason: '${e.key}/$i');
      }
    }
  });
}
