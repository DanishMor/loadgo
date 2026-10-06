import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_dashboard_screen.dart';
import 'package:transport_app/admin/flagged_users_screen.dart';
import 'package:transport_app/admin/user_risk_checks.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/geo/trip_watcher.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/risk/risk_config.dart';
import 'package:transport_app/core/risk/risk_rules.dart';
import 'package:transport_app/core/services/audit_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/device_service.dart';
import 'package:transport_app/core/services/location_service.dart';
import 'package:transport_app/core/services/risk_service.dart';
import 'package:transport_app/core/services/trip_evidence_service.dart';
import 'package:transport_app/driver/trip_geofence_banner.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String uid = 'a1';
  final now = DateTime(2026, 10, 6, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceService.resetForTest();
    db = FakeFirebaseFirestore();
    uid = 'a1';
    Backend.useFakes(db: db, uid: () => uid);
    RiskConfigStore.notifier.value = RiskConfig.defaults;
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(() {
    RiskConfigStore.notifier.value = RiskConfig.defaults;
    LocationService.useFakeCurrent(null);
    LocationService.useFake(null);
  });

  group('risk rules in config (BE13)', () {
    test('values are clamped, odd ones fall back, the map round-trips', () {
      final c = RiskConfig.fromMap({'highValuePaise': 1, 'reviewScore': 'x', 'burstLoads24h': 5000, 'cancelFlag': 4});
      expect(c.highValuePaise, 100000, reason: 'raised to the minimum');
      expect(c.reviewScore, 50, reason: 'default');
      expect(c.burstLoads24h, 1000);
      expect(c.cancelFlag, 4);
      expect(RiskConfig.fromMap(c.toMap()).toMap(), c.toMap());
      expect(RiskConfig.fromMap(null).toMap(), RiskConfig.defaults.toMap());
    });

    test('the score follows the thresholds: high value, review and hold levels, cancellations', () {
      expect(RiskRules.isHighValue(5000000), isTrue);
      expect(RiskRules.isHighValue(4999999), isFalse);
      RiskConfigStore.notifier.value = const RiskConfig(highValuePaise: 9000000, reviewScore: 30, holdScore: 40, cancelFlag: 2);
      expect(RiskRules.isHighValue(5000000), isFalse);
      expect(RiskRules.suggestReview(30), isTrue);
      expect(RiskRules.suggestHold(39), isFalse);
      expect(RiskRules.suggestHold(40), isTrue);
      expect(RiskRules.score(cancelCount: 2, openReports: 0).reasons, ['cancels_3'], reason: 'two cancels now count');
    });

    test('config/risk is read from Firestore', () async {
      await db.collection('config').doc('risk').set({'reviewScore': 20, 'manyDevices24h': 2});
      await RiskConfigStore.refresh();
      expect((RiskConfigStore.current.reviewScore, RiskConfigStore.current.manyDevices24h), (20, 2));
    });
  });

  group('behaviour score (F7)', () {
    test('bursts, phone changes, many devices and GPS mismatches add to the score with reasons', () {
      expect(RiskRules.score(cancelCount: 0, openReports: 0, loadsLast24h: 4).score, 0);
      var r = RiskRules.score(cancelCount: 0, openReports: 0, loadsLast24h: 5);
      expect(r.score, 10);
      expect(r.reasons, ['booking_burst_warn']);
      r = RiskRules.score(cancelCount: 0, openReports: 0, loadsLast24h: 12, phoneChanges30d: 2, manyDeviceSignals30d: 1, gpsMismatches30d: 2);
      expect(r.reasons, ['booking_burst', 'profile_changes', 'many_devices_24h', 'gps_mismatch']);
      expect(r.score, 70);
      expect(RiskRules.score(cancelCount: 0, openReports: 0, phoneChanges30d: 1, gpsMismatches30d: 1).score, 0);
    });

    test('flagged() adds users whose behaviour alone reaches the review level; counts come from loads and signals', () async {
      final t = now;
      await db.collection('users').doc('burst').set({'name': 'Burst', 'phone': '+911'});
      await db.collection('users').doc('calm').set({'name': 'Calm'});
      for (var i = 0; i < 12; i++) {
        await db.collection('loads').add({'shipperId': 'burst', 'createdAt': Timestamp.fromDate(t.subtract(const Duration(hours: 2))), 'status': 'open'});
      }
      await db.collection('loads').add({'shipperId': 'calm', 'createdAt': Timestamp.fromDate(t.subtract(const Duration(hours: 2))), 'status': 'open'});
      await db.collection('loads').add({'shipperId': 'burst', 'createdAt': Timestamp.fromDate(t.subtract(const Duration(days: 3))), 'status': 'open'}); // old: not counted
      for (final type in ['phone_change', 'phone_change', 'many_devices']) {
        await db.collection('risk_signals').add({'uid': 'burst', 'type': type, 'createdAt': Timestamp.fromDate(t.subtract(const Duration(days: 2)))});
      }
      await db.collection('risk_signals').add({'uid': 'calm', 'type': 'new_device', 'createdAt': Timestamp.fromDate(t.subtract(const Duration(days: 40)))});
      final list = await RiskService.flagged(now: t);
      expect(list.map((u) => u.uid), ['burst']);
      final u = list.single;
      expect((u.loadsLast24h, u.phoneChanges30d, u.manyDeviceSignals30d), (12, 2, 1));
      expect(u.assessment.score, 55);
      expect(RiskRules.suggestReview(u.assessment.score), isTrue);
      expect(RiskRules.suggestHold(u.assessment.score), isFalse);
    });
  });

  group('many devices in 24 hours (F5)', () {
    test('the third new device inside a day raises many_devices in the same batch', () async {
      for (var i = 0; i < 3; i++) {
        SharedPreferences.setMockInitialValues({});
        DeviceService.resetForTest();
        await DeviceService.register();
      }
      final types = (await db.collection('risk_signals').get()).docs.map((d) => d.data()['type']).toList();
      expect(types, ['new_device', 'new_device', 'many_devices']);
    });

    test('devices spread over days do not count; the threshold is configurable', () async {
      await db.collection('users').doc('a1').collection('devices').doc('old1').set({'label': 'x', 'trusted': true, 'revoked': false, 'firstSeenAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 9)))});
      await db.collection('users').doc('a1').collection('devices').doc('old2').set({'label': 'x', 'trusted': false, 'revoked': false, 'firstSeenAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 8)))});
      await DeviceService.register();
      expect((await db.collection('risk_signals').get()).docs.map((d) => d.data()['type']), ['new_device']);
      RiskConfigStore.notifier.value = const RiskConfig(manyDevices24h: 2);
      SharedPreferences.setMockInitialValues({});
      DeviceService.resetForTest();
      await DeviceService.register();
      expect((await db.collection('risk_signals').get()).docs.map((d) => d.data()['type']), containsAll(['many_devices']));
    });

    test('the cluster size follows the config too', () {
      final links = [for (var i = 0; i < 3; i++) (deviceId: 'd1', uid: 'u$i')];
      expect(SharedDevice.clusters(links), hasLength(1));
      RiskConfigStore.notifier.value = const RiskConfig(deviceCluster: 4);
      expect(SharedDevice.clusters(links), isEmpty);
      expect(SharedDevice.clusters(links, threshold: 3), hasLength(1));
    });
  });

  group('bulk hold (F14, free part)', () {
    test('restricts normal and review accounts with an audit event each; others are skipped', () async {
      for (final e in {'n1': 'normal', 'n2': 'review', 'r1': 'restricted', 'b1': 'banned'}.entries) {
        await db.collection('users').doc(e.key).set({'name': e.key, 'riskTier': e.value});
      }
      FlaggedUser fu(String id, String tier) => FlaggedUser(uid: id, name: id, phone: '', riskTier: tier, cancelCount: 0, openReports: 0);
      final held = await RiskService.bulkHold([fu('n1', 'normal'), fu('n2', 'review'), fu('r1', 'restricted'), fu('b1', 'banned')], reason: ' burst of loads ');
      expect(held, 2);
      for (final id in ['n1', 'n2']) {
        final d = (await db.collection('users').doc(id).get()).data()!;
        expect((d['riskTier'], d['riskReason']), ('restricted', 'burst of loads'));
      }
      expect((await db.collection('users').doc('b1').get()).data()!['riskTier'], 'banned');
      final audit = (await db.collection('audit_events').get()).docs.map((d) => d.data()).toList();
      expect(audit.length, 2);
      expect(audit.every((e) => e['type'] == AuditType.riskChange && (e['data'] as Map)['bulk'] == true), isTrue);
    });

    testWidgets('flagged screen: select the high scores, confirm, accounts are restricted', (tester) async {
      await tester.runAsync(() async {
        await db.collection('users').doc('hot').set({'name': 'Hot', 'phone': '+911', 'cancelCount': 6});
        await db.collection('users').doc('mild').set({'name': 'Mild', 'phone': '+912', 'cancelCount': 3});
        await db.collection('risk_signals').add({'uid': 'hot', 'type': 'many_devices', 'createdAt': Timestamp.now()});
        await db.collection('risk_signals').add({'uid': 'hot', 'type': 'gps_mismatch', 'createdAt': Timestamp.now()});
        await db.collection('risk_signals').add({'uid': 'hot', 'type': 'gps_mismatch', 'createdAt': Timestamp.now()});
      });
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: FlaggedUsersScreen())));
      await settle(tester);
      expect(find.text('Many new devices in 24 h', skipOffstage: false), findsNothing, reason: 'reasons are part of the subtitle line');
      await tester.tap(find.byKey(const ValueKey('selectHold')));
      await tester.pumpAndSettle();
      expect((tester.widget<Checkbox>(find.byKey(const ValueKey('flagPick_hot')))).value, isTrue);
      expect((tester.widget<Checkbox>(find.byKey(const ValueKey('flagPick_mild')))).value, isFalse);
      await tester.tap(find.byKey(const ValueKey('holdSelected')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('holdConfirm')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('users').doc('hot').get()))!.data()!['riskTier'], 'restricted');
      expect((await tester.runAsync(() => db.collection('users').doc('mild').get()))!.data()!.containsKey('riskTier'), isFalse);
    });
  });

  group('possible duplicate accounts (F1)', () {
    test('pure: shared device and same name, strongest first, the account itself never', () {
      final r = RiskRules.duplicates('u1', {'u1': {'d1', 'd2'}, 'u2': {'d2'}, 'u3': {'d9'}, 'u4': {'d1', 'd2'}}, {'u2', 'u5', 'u1'});
      expect(r.map((c) => c.uid), ['u2', 'u4', 'u5']);
      expect(r.first.reasons, ['shared_device', 'same_name']);
      expect(r[1].reasons, ['shared_device']);
      expect(r[1].sharedDevices, 2);
      expect(r.last.reasons, ['same_name']);
      expect(RiskRules.nameKey('  Ramesh   K. Sharma '), 'ramesh k sharma');
      expect(RiskRules.nameKey('रमेश  कुमार'), 'रमेश कुमार');
    });

    test('service: finds accounts on the same device and with the same name; ignores short or different names', () async {
      await db.collection('users').doc('a1').set({'name': 'Ramesh Kumar'});
      await db.collection('users').doc('a2').set({'name': 'Ramesh Kumar'});
      await db.collection('users').doc('a3').set({'name': 'Suresh'});
      await db.collection('users').doc('a4').set({'name': 'ramesh kumar'});
      await db.collection('device_links').doc('dv1_a1').set({'deviceId': 'dv1', 'uid': 'a1'});
      await db.collection('device_links').doc('dv1_a3').set({'deviceId': 'dv1', 'uid': 'a3'});
      await db.collection('device_links').doc('dv2_a1').set({'deviceId': 'dv2', 'uid': 'a1'});
      final c = await RiskService.duplicatesOf('a1');
      final by = {for (final x in c) x.uid: x.reasons};
      expect(by, {'a2': ['same_name'], 'a3': ['shared_device']});
      await db.collection('users').doc('b1').set({'name': 'Raj'});
      await db.collection('users').doc('b2').set({'name': 'Raj'});
      expect(await RiskService.duplicatesOf('b1'), isEmpty, reason: 'names under 4 letters are not enough');
    });

    testWidgets('the admin user card lists them and says so when there are none', (tester) async {
      await tester.runAsync(() async {
        await db.collection('users').doc('a1').set({'name': 'Ramesh Kumar', 'driverName': 'Ramesh Kumar'});
        await db.collection('users').doc('a2').set({'name': 'Ramesh Kumar'});
      });
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: Scaffold(body: UserRiskChecks(uid: 'a1', isDriver: false)))));
      await settle(tester);
      expect(find.byKey(const ValueKey('dup_a2')), findsOneWidget);
      expect(find.text('Same name'), findsOneWidget);
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: UserRiskChecks(key: UniqueKey(), uid: 'zz', isDriver: false)))));
      await settle(tester);
      expect(find.byKey(const ValueKey('dupNone')), findsOneWidget);
    });
  });

  group('vehicle and RC checks (F3)', () {
    Vehicle v(String number, String rc, {String id = 'v'}) =>
        Vehicle(id: id, ownerId: 'a1', number: number, type: '20ft', capacity: 10, rcNumber: rc, status: 'active');

    test('same plate fine; another state or another number is flagged; free-form RC numbers are not judged', () {
      expect(RiskRules.vehicleAnomalies(v('MH12AB1234', 'MH12AB1234')), isEmpty);
      expect(RiskRules.vehicleAnomalies(v('MH 12 AB 1234', 'mh12ab1234')), isEmpty);
      expect(RiskRules.vehicleAnomalies(v('MH12AB1234', 'GJ01CD5678')), ['rc_state_differs']);
      expect(RiskRules.vehicleAnomalies(v('MH12AB1234', 'MH14XY9999')), ['rc_number_differs']);
      expect(RiskRules.vehicleAnomalies(v('MH12AB1234', 'RC-0099/2020')), isEmpty);
    });

    test('service: flagged vehicles of a driver; more than five vehicles on a non-fleet account', () async {
      await db.collection('users').doc('a1').set({'role': 'driver'});
      for (var i = 0; i < 6; i++) {
        await db.collection('vehicles').doc('v$i').set({'ownerId': 'a1', 'number': 'MH12AB000$i', 'type': '20ft', 'capacity': 10, 'rcNumber': i == 2 ? 'GJ01CD5678' : 'MH12AB000$i', 'status': 'active'});
      }
      final checks = await RiskService.vehicleChecks('a1');
      expect(checks.map((e) => e.vehicle.id), ['v2']);
      expect(await RiskService.tooManyVehicles('a1'), isTrue);
      await db.collection('users').doc('a1').set({'role': 'fleet'});
      expect(await RiskService.tooManyVehicles('a1'), isFalse);
    });
  });

  group('staff roles (BE7)', () {
    test('super sees everything; others only their areas; unknown role is treated as super', () {
      for (final area in staffAreas.keys) {
        expect(staffCan(StaffRole.superAdmin, area), isTrue, reason: area);
        expect(staffCan(null, area), isTrue, reason: 'no role = super: $area');
      }
      expect(staffCan(StaffRole.support, 'adminTickets'), isTrue);
      expect(staffCan(StaffRole.support, 'driverVerification'), isFalse);
      expect(staffCan(StaffRole.verifier, 'driverVerification'), isTrue);
      expect(staffCan(StaffRole.verifier, 'adminTickets'), isFalse);
      expect(staffCan(StaffRole.ops, 'flaggedUsers'), isTrue);
      expect(staffCan(StaffRole.ops, 'adminConfig'), isFalse);
      expect(staffCan(StaffRole.support, 'adminConfig'), isFalse);
      expect(staffCan('nonsense', 'adminConfig'), isTrue);
      expect(staffCan('support', 'unknownArea'), isFalse);
    });

    testWidgets('the dashboard of a support user hides what that role cannot act on and shows the role', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => db.collection('admins').doc('a1').set({'role': 'support'}));
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: AdminDashboardScreen())));
      await settle(tester);
      expect(find.byKey(const ValueKey('admin_adminTickets')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin_adminDisputes')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin_driverVerification')), findsNothing);
      expect(find.byKey(const ValueKey('admin_adminConfig')), findsNothing);
      expect(find.byKey(const ValueKey('admin_flaggedUsers')), findsNothing);
      expect(find.text('Support'), findsOneWidget);
    });
  });

  group('GPS loss and low network (TEST5)', () {
    test('no position sample means no signal; a long gap then a far sample is movement, not a halt', () {
      final w = TripWatcher(dropPlace: 'Delhi');
      expect(w.signals(now).any, isFalse);
      w.add(now.subtract(const Duration(hours: 1)), 19.0, 73.0);
      expect(w.signals(now).longHalt, isTrue, reason: 'silence at one spot for an hour');
      w.add(now, 21.0, 74.5);
      expect(w.signals(now).longHalt, isFalse, reason: 'the phone moved after the gap');
    });

    test('saveGps without a fix returns false and writes nothing, also when the fix fails with an error', () async {
      await db.collection('bookings').doc('b1').set({'driverId': 'a1', 'customerId': 'c1', 'status': 'picked_up', 'pickup': 'Pune', 'drop': 'Delhi'});
      LocationService.useFakeCurrent(() async => null);
      expect(await TripEvidenceService.saveGps('b1', pickup: true, place: 'Pune'), isFalse);
      LocationService.useFakeCurrent(() async => throw StateError('gps off'));
      await expectLater(TripEvidenceService.saveGps('b1', pickup: true), throwsStateError);
      expect((await db.collection('bookings').doc('b1').get()).data()!.containsKey('pickupGps'), isFalse);
      expect((await db.collection('audit_events').get()).docs, isEmpty);
    });

    testWidgets('the geofence banner survives a position stream that fails and keeps working with the samples that follow', (tester) async {
      final c = StreamController<Coordinates>();
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: TripGeofenceBanner(dropPlace: 'Delhi', positions: c.stream, now: () => now)))));
      c.add((lat: 25.0, lng: 76.0));
      await tester.pump(const Duration(milliseconds: 20));
      c.addError(StateError('GPS signal lost'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull);
      c.add((lat: 28.61, lng: 77.21));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byKey(const ValueKey('geoReached')), findsOneWidget);
      await c.close();
    });

    testWidgets('no permission or no fix: the banner stays empty instead of crashing', (tester) async {
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: TripGeofenceBanner(dropPlace: 'Delhi', positions: const Stream.empty(), now: () => now)))));
      await tester.pump();
      expect(find.byType(Card), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
