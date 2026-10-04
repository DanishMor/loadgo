import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_verification_screen.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/identity/masking.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/matching/load_ranker.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/reminders/reminders.dart';
import 'package:transport_app/core/services/admin_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/user_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/widgets/verification_badges.dart';
import 'package:transport_app/driver/add_vehicle_screen.dart';
import 'package:transport_app/driver/my_vehicles_screen.dart';

import 'test_utils.dart';

Vehicle veh({VehicleProfile profile = const VehicleProfile(), DateTime? tyre}) => Vehicle(
      id: 'v', ownerId: 'd1', number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active',
      profile: profile, nextTyreCheckDate: tyre,
    );

Load load0(String pickup, {String id = 'a'}) => Load(
      id: id, shipperId: 'c1', pickup: pickup, drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft',
      budget: 1000, pickupDate: null, notes: '', status: 'open',
    );

void main() {
  late FakeFirebaseFirestore db;
  String uid = 'd1';
  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'd1';
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });

  group('V2 vehicle profile', () {
    test('profile validation and text', () {
      expect(const VehicleProfile().isEmpty, isTrue);
      expect(const VehicleProfile(lengthM: 6.1, widthM: 2.4, heightM: 2.4, fuel: 'diesel', bodyType: 'closed').valid, isTrue);
      expect(const VehicleProfile(lengthM: 0).valid, isFalse);
      expect(const VehicleProfile(lengthM: 31).valid, isFalse);
      expect(const VehicleProfile(fuel: 'coal').valid, isFalse);
      expect(const VehicleProfile(bodyType: 'boat').valid, isFalse);
      expect(const VehicleProfile(lengthM: 6, widthM: 2.4).dimensionsText, '6 × 2.4 × - m');
      expect(const VehicleProfile().dimensionsText, isNull);
    });

    test('add stores the profile; update changes and clears it; bad values are refused', () async {
      final id = await VehicleService.add(
        number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1',
        profile: const VehicleProfile(lengthM: 6.1, widthM: 2.4, heightM: 2.4, fuel: 'diesel', bodyType: 'closed'),
      );
      var v = Vehicle.fromDoc(await db.collection('vehicles').doc(id).get());
      expect(v.profile.lengthM, 6.1);
      expect(v.profile.fuel, 'diesel');
      expect(v.profile.bodyType, 'closed');

      await VehicleService.update(
        vehicleId: id, number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1',
        profile: const VehicleProfile(lengthM: 7, fuel: 'cng'),
      );
      v = Vehicle.fromDoc(await db.collection('vehicles').doc(id).get());
      expect(v.profile.lengthM, 7);
      expect(v.profile.widthM, isNull, reason: 'cleared');
      expect(v.profile.bodyType, isNull);
      expect(v.profile.fuel, 'cng');

      // update without a profile leaves it alone
      await VehicleService.update(vehicleId: id, number: 'MH12AB1234', type: '20ft', capacity: 11, rcNumber: 'RC1');
      expect(Vehicle.fromDoc(await db.collection('vehicles').doc(id).get()).profile.fuel, 'cng');

      await expectLater(
        VehicleService.add(number: 'MH12AB9999', type: '20ft', capacity: 10, rcNumber: 'RC2', profile: const VehicleProfile(fuel: 'coal')),
        throwsArgumentError,
      );
    });

    test('old vehicles without the fields still read', () async {
      await db.collection('vehicles').doc('old').set({'ownerId': 'd1', 'number': 'X', 'type': 'Mini', 'capacity': 1, 'status': 'active'});
      expect(Vehicle.fromDoc(await db.collection('vehicles').doc('old').get()).profile.isEmpty, isTrue);
    });

    testWidgets('the form saves dimensions, fuel and body type; the list shows them', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: AddVehicleScreen())));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'MH12AB1234');
      await tester.enterText(find.byType(TextFormField).at(1), '9');
      await tester.enterText(find.byType(TextFormField).at(2), 'RC123');
      await tester.enterText(find.byKey(const ValueKey('vehLength')), '6.1');
      await tester.enterText(find.byKey(const ValueKey('vehWidth')), '2.4');
      await tester.tap(find.byKey(const ValueKey('vehFuel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diesel').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ElevatedButton).last);
      await tester.tap(find.byType(ElevatedButton).last);
      await settle(tester);
      final d = (await tester.runAsync(() => db.collection('vehicles').get()))!.docs.single.data();
      expect(d['lengthM'], 6.1);
      expect(d['widthM'], 2.4);
      expect(d['fuel'], 'diesel');
      expect(d.containsKey('heightM'), isFalse);
    });

    testWidgets('a too-large dimension is refused by the form', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: AddVehicleScreen())));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('vehHeight')), '99');
      await tester.ensureVisible(find.byType(ElevatedButton).last);
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid number'), findsWidgets);
      expect((await tester.runAsync(() => db.collection('vehicles').get()))!.docs, isEmpty);
    });
  });

  group('V8 tyre check + document reminders', () {
    final now = DateTime(2026, 10, 8, 12);

    test('tyre check due within a week', () {
      expect(veh(tyre: DateTime(2026, 10, 12)).tyreDue(now), isTrue);
      expect(veh(tyre: DateTime(2026, 10, 1)).tyreDue(now), isTrue);
      expect(veh(tyre: DateTime(2026, 11, 1)).tyreDue(now), isFalse);
      expect(veh().tyreDue(now), isFalse);
    });

    test('the reminder engine reports tyres, papers and licence together', () {
      final r = ReminderEngine.compute(ReminderInput(
        now: now, isDriver: true, vehicles: [veh(tyre: DateTime(2026, 10, 10))], licenceExpiry: DateTime(2026, 10, 20),
      ));
      expect(r.map((x) => x.kind), containsAll([ReminderKind.tyreDue, ReminderKind.licenceExpiring]));
    });

    test('saving documents stores or clears the tyre date', () async {
      final id = await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
      await VehicleService.saveDocuments(id, const {}, nextTyreCheckDate: DateTime(2026, 11, 5));
      expect(Vehicle.fromDoc(await db.collection('vehicles').doc(id).get()).nextTyreCheckDate, DateTime(2026, 11, 5));
      await VehicleService.saveDocuments(id, const {});
      expect(Vehicle.fromDoc(await db.collection('vehicles').doc(id).get()).nextTyreCheckDate, isNull);
    });
  });

  group('B9 fragile and high value', () {
    test('flags are stored on the load and read back', () async {
      uid = 'c1';
      Future<Load> post({bool f = false, bool h = false}) async {
        final id = await LoadService.post(
          pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 1000,
          pickupDate: DateTime(2026, 10, 5), notes: '', fragile: f, highValue: h,
        );
        return Load.fromDoc(await db.collection('loads').doc(id).get());
      }

      final plain = await post();
      expect(plain.fragile, isFalse);
      expect(plain.highValue, isFalse);
      final both = await post(f: true, h: true);
      expect(both.fragile, isTrue);
      expect(both.highValue, isTrue);
    });
  });

  group('SM8 risk filter and SM1 live position', () {
    final now = DateTime(2026, 10, 4);
    DriverContext ctx({String tier = 'normal', ({double lat, double lng})? origin, String? anchor, bool active = false}) => DriverContext(
          vehicles: [veh()], now: now, riskTier: tier, origin: origin, anchorPlace: anchor, anchorIsActiveTrip: active);

    test('only normal and review drivers get matches', () {
      expect(LoadRanker.matchFor(load0('Delhi'), ctx()), isNotNull);
      expect(LoadRanker.matchFor(load0('Delhi'), ctx(tier: 'review')), isNotNull);
      expect(LoadRanker.matchFor(load0('Delhi'), ctx(tier: 'restricted')), isNull);
      expect(LoadRanker.matchFor(load0('Delhi'), ctx(tier: 'suspended')), isNull);
      expect(LoadRanker.rank([load0('Delhi')], ctx(tier: 'suspended')), isEmpty);
    });

    test('the saved position decides "near pickup" when there is no trip; an active trip keeps the drop anchor', () {
      const nearDelhi = (lat: 28.7, lng: 77.1);
      final fromHere = LoadRanker.matchFor(load0('Delhi'), ctx(origin: nearDelhi, anchor: 'Chennai'))!;
      expect(fromHere.reasons, contains(MatchReason.nearPickup));
      final farLoad = LoadRanker.matchFor(load0('Mumbai'), ctx(origin: nearDelhi, anchor: 'Mumbai'))!;
      expect(farLoad.reasons, isNot(contains(MatchReason.nearPickup)), reason: 'the position wins over the old anchor');
      final onTrip = LoadRanker.matchFor(load0('Mumbai'), DriverContext(
          vehicles: [veh(profile: const VehicleProfile())].map((v) => Vehicle(id: 'v', ownerId: 'd1', number: 'X', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active', availability: VehicleAvailability.onTrip)).toList(),
          now: now, origin: nearDelhi, anchorPlace: 'Mumbai', anchorIsActiveTrip: true))!;
      expect(onTrip.reasons, containsAll([MatchReason.nearPickup, MatchReason.returnLoad]));
    });

    test('closer pickups from the live position score higher', () {
      const delhi = (lat: 28.61, lng: 77.21);
      final near = LoadRanker.matchFor(load0('Delhi'), ctx(origin: delhi))!;
      final far = LoadRanker.matchFor(load0('Chennai'), ctx(origin: delhi))!;
      expect(near.score, greaterThan(far.score));
    });
  });

  group('D2 online switch is saved', () {
    test('setOnline writes the flag and the time', () async {
      await UserService.setOnline(true);
      var u = (await db.collection('users').doc('d1').get()).data()!;
      expect(u['online'], true);
      expect(u['onlineChangedAt'], isNotNull);
      await UserService.setOnline(false);
      u = (await db.collection('users').doc('d1').get()).data()!;
      expect(u['online'], false);
    });
  });

  group('K11 / DOC11 / K14', () {
    test('masking', () {
      expect(maskId('ABCDE1234F'), 'AB••••••4F');
      expect(maskId('MH1220110012345'), 'MH•••••••••••45');
      expect(maskId('1234'), '••••');
      expect(maskId(''), '');
      expect(maskId(null), '');
      expect(maskAadhaarLast4('4321'), '•••• •••• 4321');
      expect(maskAadhaarLast4(''), '');
    });

    final kyc = {'dlNumber': 'MH1220110012345', 'pan': 'ABCDE1234F', 'rcNumber': 'MH12AB1234', 'aadhaarLast4': '4321'};

    test('per-type states: OTP, provided and unverified, reviewed, missing', () {
      final pending = verificationBadges({'phone': '+919800000000', 'driverKyc': {'dlNumber': 'MH1220110012345'}}, isDriver: true);
      BadgeState st(List<BadgeItem> l, String key) => l.firstWhere((b) => b.labelKey == key).state;
      expect(st(pending, 'phone'), BadgeState.verifiedByOtp);
      expect(st(pending, 'dlNumber'), BadgeState.providedUnverified);
      expect(st(pending, 'panNumber'), BadgeState.missing);
      final approved = verificationBadges({'phone': '+91', 'verified': true, 'driverKyc': kyc}, isDriver: true);
      expect(st(approved, 'dlNumber'), BadgeState.reviewed);
      expect(st(approved, 'aadhaarLast4'), BadgeState.reviewed);
      final customer = verificationBadges({'phone': '+91', 'business': {'gstin': '27ABCDE1234F1Z5'}}, isDriver: false);
      expect(customer.map((b) => b.labelKey), ['phone', 'gstin']);
      expect(st(customer, 'gstin'), BadgeState.providedUnverified);
      expect(verificationBadges({'phone': '+91'}, isDriver: false).map((b) => b.labelKey), ['phone']);
    });

    testWidgets('badges show masked numbers and reveal on request', (tester) async {
      Widget w(bool reveal) => LanguageScope(
          notifier: languageNotifier,
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: VerificationBadges(user: {'phone': '+91', 'driverKyc': kyc}, isDriver: true, reveal: reveal)))));
      await tester.pumpWidget(w(false));
      expect(find.text('AB••••••4F'), findsOneWidget);
      expect(find.text('ABCDE1234F'), findsNothing);
      expect(find.text('•••• •••• 4321'), findsOneWidget);
      await tester.pumpWidget(w(true));
      expect(find.text('ABCDE1234F'), findsOneWidget);
    });

    test('approving writes who, how and when; the rejection too', () async {
      uid = 'admin1';
      await db.collection('users').doc('d9').set({'driverName': 'R', 'verificationStatus': 'pending', 'verified': false});
      await AdminService.setStatus('d9', AdminService.approved);
      var u = (await db.collection('users').doc('d9').get()).data()!;
      final meta = u['verificationMeta'] as Map;
      expect(meta['source'], 'manual_review');
      expect(meta['by'], 'admin1');
      expect(meta['status'], 'approved');
      expect(meta['at'], isNotNull);
      expect(reviewInfo(u)!.source, 'manual_review');
      await AdminService.setStatus('d9', AdminService.rejected);
      u = (await db.collection('users').doc('d9').get()).data()!;
      expect((u['verificationMeta'] as Map)['status'], 'rejected');
    });

    testWidgets('admin queue shows the driver\'s documents masked, with a reveal switch', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => db.collection('users').doc('d9').set({
            'driverName': 'Ramesh', 'phone': '+919800000000', 'verificationStatus': 'pending', 'driverKyc': kyc,
          }));
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: AdminVerificationScreen())));
      await settle(tester);
      expect(find.text('AB••••••4F'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reveal_d9')));
      await tester.pump();
      expect(find.text('ABCDE1234F'), findsOneWidget);
    });
  });

  testWidgets('my vehicles list shows body, fuel and size', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final id = (await tester.runAsync(() => VehicleService.add(
        number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1',
        profile: const VehicleProfile(lengthM: 6, widthM: 2.4, heightM: 2.4, fuel: 'diesel', bodyType: 'closed'))))!;
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: MyVehiclesScreen())));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(ValueKey('profile_$id'))).data, 'Closed body • Diesel • 6 × 2.4 × 2.4 m');
  });
}
