import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_signals_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/risk.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/risk/risk_rules.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/device_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/settings/devices_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String uid = 'u1';
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceService.resetForTest();
    db = FakeFirebaseFirestore();
    uid = 'u1';
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });

  Widget app(Widget w) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: w));

  group('devices', () {
    test('the device id is random, saved and stable', () async {
      final a = await DeviceService.deviceId();
      expect(a, matches(RegExp(r'^[a-z0-9]{24}$')));
      DeviceService.resetForTest();
      expect(await DeviceService.deviceId(), a);
    });

    test('first device is trusted; a second device is new and raises a signal; links are written', () async {
      expect(await DeviceService.register(), DeviceCheck.first);
      var d = (await DeviceService.watchMine().first).single;
      expect((d.trusted, d.revoked), (true, false));
      expect(await DeviceService.register(), DeviceCheck.known);
      expect((await db.collection('risk_signals').get()).docs, isEmpty);

      // the same account from another phone
      SharedPreferences.setMockInitialValues({});
      DeviceService.resetForTest();
      expect(await DeviceService.register(), DeviceCheck.newDevice);
      final devices = await DeviceService.watchMine().first;
      expect(devices, hasLength(2));
      expect(devices.where((x) => !x.trusted), hasLength(1));
      final sig = (await db.collection('risk_signals').get()).docs.single.data();
      expect(sig['type'], 'new_device');
      expect(sig['uid'], 'u1');
      expect((await db.collection('device_links').get()).docs, hasLength(2));
    });

    test('revoke signs a device out; signing in there again brings it back', () async {
      await DeviceService.register();
      final id = await DeviceService.deviceId();
      expect(await DeviceService.sessionRevoked(), isFalse);
      await DeviceService.revoke(id);
      expect(await DeviceService.sessionRevoked(), isTrue);
      await DeviceService.register();
      expect(await DeviceService.sessionRevoked(), isFalse);
    });

    test('log out everywhere revokes the others and marks the profile; this device stays', () async {
      await DeviceService.register();
      final mine = await DeviceService.deviceId();
      await db.collection('users').doc('u1').collection('devices').doc('otherphone1234').set({
        'label': 'android', 'trusted': true, 'revoked': false, 'firstSeenAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'lastSeenAt': Timestamp.fromDate(DateTime(2026, 1, 1)), 'lastLoginAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await DeviceService.logOutEverywhere();
      final devices = {for (final d in await DeviceService.watchMine().first) d.id: d};
      expect(devices['otherphone1234']!.revoked, isTrue);
      expect(devices[mine]!.revoked, isFalse);
      expect((await db.collection('users').doc('u1').get()).data()!['sessionsRevokedAt'], isNotNull);
      expect(await DeviceService.sessionRevoked(), isFalse, reason: 'this device logged in after the revoke');
    });

    test('a device whose login is older than the revoke time is signed out', () async {
      await DeviceService.register();
      final id = await DeviceService.deviceId();
      await db.collection('users').doc('u1').collection('devices').doc(id).update({'lastLoginAt': Timestamp.fromDate(DateTime(2026, 1, 1))});
      await db.collection('users').doc('u1').set({'sessionsRevokedAt': Timestamp.fromDate(DateTime(2026, 6, 1))}, SetOptions(merge: true));
      expect(await DeviceService.sessionRevoked(), isTrue);
    });

    test('same-device clusters need 3 or more accounts', () {
      final links = [
        for (final u in ['a', 'b', 'c']) (deviceId: 'dev1', uid: u),
        (deviceId: 'dev2', uid: 'a'),
        (deviceId: 'dev2', uid: 'b'),
        (deviceId: 'dev3', uid: 'x'),
        (deviceId: 'dev1', uid: 'a'),
      ];
      final c = SharedDevice.clusters(links);
      expect(c, hasLength(1));
      expect(c.single.deviceId, 'dev1');
      expect(c.single.uids, ['a', 'b', 'c']);
      expect(SharedDevice.clusters(links, threshold: 2), hasLength(2));
    });

    testWidgets('devices screen: trust, revoke, log out everywhere', (tester) async {
      await tester.runAsync(() async {
        await DeviceService.register();
        await db.collection('users').doc('u1').collection('devices').doc('otherphone1234').set({
          'label': 'ios', 'trusted': false, 'revoked': false, 'firstSeenAt': Timestamp.now(), 'lastSeenAt': Timestamp.now(),
        });
      });
      await tester.pumpWidget(app(const DevicesScreen()));
      await settle(tester);
      expect(find.text('New'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trust_otherphone1234')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('users').doc('u1').collection('devices').doc('otherphone1234').get()))!.data()!['trusted'], true);
      await tester.tap(find.byKey(const ValueKey('revoke_otherphone1234')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('users').doc('u1').collection('devices').doc('otherphone1234').get()))!.data()!['revoked'], true);
      await tester.tap(find.byKey(const ValueKey('logOutEverywhere')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('everywhereConfirm')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('users').doc('u1').get()))!.data()!['sessionsRevokedAt'], isNotNull);
    });
  });

  group('R5 / R6 / R8 risk rules', () {
    test('high value threshold is Rs 50,000', () {
      expect(RiskRules.isHighValue(4999999), isFalse);
      expect(RiskRules.isHighValue(5000000), isTrue);
    });

    test('score adds up and suggests review at 50', () {
      expect(RiskRules.score(cancelCount: 0, openReports: 0).score, 0);
      final mid = RiskRules.score(cancelCount: 3, openReports: 1);
      expect(mid.score, 35);
      expect(mid.reasons, ['cancels_3', 'open_reports']);
      expect(RiskRules.suggestReview(mid.score), isFalse);
      final bad = RiskRules.score(cancelCount: 6, openReports: 2, newDevicesLast7Days: 2, expiredPapers: 1, tier: RiskTier.review);
      expect(bad.score, 40 + 30 + 20 + 15 + 10);
      expect(RiskRules.suggestReview(bad.score), isTrue);
      expect(RiskRules.score(cancelCount: 0, openReports: 10).score, 45, reason: 'reports are capped');
      expect(RiskRules.score(cancelCount: 0, openReports: 0, tier: RiskTier.suspended).score, 50);
    });

    test('a random sample has no repeats, respects n and is repeatable with a seed', () {
      final all = List.generate(20, (i) => i);
      final a = RiskRules.randomSample(all, 5, seed: 7);
      expect(a.toSet().length, 5);
      expect(RiskRules.randomSample(all, 5, seed: 7), a);
      expect(RiskRules.randomSample(all, 50), hasLength(20));
      expect(all, hasLength(20), reason: 'input untouched');
    });

    test('posting a high-value load writes a signal for admins; a normal one does not', () async {
      Future<void> post(int total) => LoadService.post(
            pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null,
            pickupDate: DateTime(2026, 10, 5), notes: '',
            estimate: FareCalculator.calculate(rule: PricingRule(baseFare: total, perKm: 0, minimumFare: 0), distanceKm: 0),
          );
      await post(100000);
      expect((await db.collection('risk_signals').get()).docs, isEmpty);
      await post(6000000);
      final s = (await db.collection('risk_signals').get()).docs.single.data();
      expect(s['type'], 'high_value');
      expect(s['amountPaise'], 6000000);
      expect(s['uid'], 'u1');
    });

    testWidgets('admin screen: signals, shared devices and the random check', (tester) async {
      await tester.runAsync(() async {
        await db.collection('risk_signals').add({'uid': 'u9', 'type': 'high_value', 'amountPaise': 7000000, 'note': 'load X', 'createdAt': Timestamp.now()});
        for (final u in ['a', 'b', 'c']) {
          await db.collection('device_links').doc('devX_$u').set({'deviceId': 'devX', 'uid': u, 'createdAt': Timestamp.now()});
        }
        await db.collection('users').doc('d1').set({'driverName': 'Ramesh', 'phone': '+91', 'verificationStatus': 'approved', 'verified': true});
      });
      uid = 'admin1';
      await tester.pumpWidget(app(const AdminSignalsScreen()));
      await settle(tester);
      expect(find.textContaining('High-value load · u9'), findsOneWidget);
      await tester.tap(find.text('Shared devices'));
      await settle(tester);
      expect(find.text('3 accounts on one device'), findsOneWidget);
      await tester.tap(find.text('Random check').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drawSample')));
      await settle(tester);
      expect(find.byKey(const ValueKey('sample_d1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reverify_d1')));
      await settle(tester);
      final u = (await tester.runAsync(() => db.collection('users').doc('d1').get()))!.data()!;
      expect(u['verificationStatus'], 'pending');
      expect(u['verified'], false);
    });
  });
}
