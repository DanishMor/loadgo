import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_driver_rewards_screen.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/driver_extras.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/driver_extras_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/payment_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/widgets/tip_card.dart';
import 'package:transport_app/driver/driver_rewards_screen.dart';

import 'test_utils.dart';

final base = DateTime(2026, 10, 1);

Incentive incentive({int trips = 3, int days = 7, int bonus = 50000, DateTime? starts, bool active = true}) => Incentive(
      id: 'inc1', title: 'Weekly 3', targetTrips: trips, windowDays: days, bonusPaise: bonus, startsAt: starts ?? base, active: active);

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'driver1';
    Backend.useFakes(db: db, uid: () => uid);
    PricingService.reset();
    languageNotifier.value = AppLanguage.english;
  });

  Future<Booking> booking(String id, {String status = 'delivered', DateTime? at, String customer = 'customer1', String driver = 'driver1'}) async {
    await db.collection('bookings').doc(id).set({
      'driverId': driver,
      'customerId': customer,
      'status': status,
      'pickup': 'A',
      'drop': 'B',
      'timeline': {'delivered': ?(at == null ? null : Timestamp.fromDate(at))},
    });
    return Booking.fromDoc(await db.collection('bookings').doc(id).get());
  }

  group('tips', () {
    test('customer tips a delivered booking once; the driver sees the total', () async {
      final b = await booking('b1');
      uid = 'customer1';
      await DriverExtrasService.addTip(b, 5000);
      final d = (await db.collection('tips').doc('b1').get()).data()!;
      expect(d['amountPaise'], 5000);
      expect(d['driverId'], 'driver1');
      await expectLater(DriverExtrasService.addTip(b, 2000), throwsA(isA<TipException>().having((e) => e.reason, 'reason', 'already')));
      uid = 'driver1';
      expect(Tip.total(await DriverExtrasService.watchMyTips().first), 5000);
    });

    test('refuses bad amounts, other people\'s bookings and trips not yet delivered', () async {
      final done = await booking('b1');
      final moving = await booking('b2', status: 'in_transit');
      uid = 'customer1';
      await expectLater(DriverExtrasService.addTip(done, 50), throwsA(isA<TipException>()));
      await expectLater(DriverExtrasService.addTip(done, Tip.maxPaise + 1), throwsA(isA<TipException>()));
      await expectLater(DriverExtrasService.addTip(moving, 5000), throwsA(isA<TipException>().having((e) => e.reason, 'reason', 'not_delivered')));
      uid = 'someoneElse';
      await expectLater(DriverExtrasService.addTip(done, 5000), throwsA(isA<TipException>().having((e) => e.reason, 'reason', 'not_yours')));
      expect((await db.collection('tips').get()).docs, isEmpty);
    });

    testWidgets('tip card: quick amount records the tip and shows it', (tester) async {
      final b = await tester.runAsync(() => booking('b1'));
      uid = 'customer1';
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: TipCard(booking: b!)))));
      await settle(tester);
      expect(find.byKey(const ValueKey('tip_5000')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tip_5000')));
      await settle(tester);
      expect(find.byKey(const ValueKey('tipGiven')), findsOneWidget);
      expect(find.byKey(const ValueKey('tip_5000')), findsNothing);
    });
  });

  group('incentives', () {
    test('trips are counted inside the window, delivered only', () async {
      final list = [
        await booking('a', at: base.add(const Duration(days: 1))),
        await booking('b', at: base.add(const Duration(days: 7))), // last moment of the window
        await booking('c', at: base.subtract(const Duration(hours: 1))), // before
        await booking('d', at: base.add(const Duration(days: 8))), // after
        await booking('e', status: 'in_transit', at: base.add(const Duration(days: 2))),
      ];
      final i = incentive();
      expect(i.tripsDone(list), 2);
      expect(i.progress(list), closeTo(2 / 3, 1e-9));
      expect(i.reached(list), isFalse);
      expect(incentive(trips: 2).reached(list), isTrue);
    });

    test('claiming needs the target, the window (plus 7 days of grace) and an active incentive', () async {
      final list = [for (var n = 0; n < 3; n++) await booking('t$n', at: base.add(Duration(days: n)))];
      final i = incentive();
      expect(i.canClaim(list, base.add(const Duration(days: 3))), isTrue);
      expect(i.canClaim(list, base.add(const Duration(days: 14))), isTrue);
      expect(i.canClaim(list, base.add(const Duration(days: 15))), isFalse);
      expect(i.canClaim(list, base.subtract(const Duration(days: 1))), isFalse);
      expect(incentive(active: false).canClaim(list, base.add(const Duration(days: 3))), isFalse);
      expect(incentive(trips: 4).canClaim(list, base.add(const Duration(days: 3))), isFalse);
    });

    test('a claim is stored once per driver and an admin marks it paid', () async {
      final list = [for (var n = 0; n < 3; n++) await booking('t$n', at: DateTime.now())];
      final i = Incentive(id: 'inc1', title: 'x', targetTrips: 3, windowDays: 7, bonusPaise: 50000, startsAt: DateTime.now().subtract(const Duration(days: 1)));
      await DriverExtrasService.claim(i, list);
      final c = (await db.collection('incentive_claims').doc('inc1_driver1').get()).data()!;
      expect(c['bonusPaise'], 50000);
      expect(c['status'], 'claimed');
      await expectLater(DriverExtrasService.claim(i, list), throwsA(isA<ClaimException>().having((e) => e.reason, 'reason', 'already')));
      await expectLater(DriverExtrasService.claim(incentive(trips: 9), list), throwsA(isA<ClaimException>().having((e) => e.reason, 'reason', 'not_reached')));
      await DriverExtrasService.markClaimPaid('inc1_driver1');
      expect((await db.collection('incentive_claims').doc('inc1_driver1').get()).data()!['status'], 'paid');
    });

    test('admin saves incentives; drivers only see active ones', () async {
      await DriverExtrasService.saveIncentive(incentive());
      await DriverExtrasService.saveIncentive(incentive(active: false));
      expect((await DriverExtrasService.watchIncentives().first), hasLength(1));
      expect((await DriverExtrasService.watchIncentives(onlyActive: false).first), hasLength(2));
    });

    testWidgets('driver screen shows progress and a claim button once the target is met', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final id = await tester.runAsync(() async {
        for (var n = 0; n < 2; n++) {
          await booking('t$n', at: DateTime.now());
        }
        final ref = db.collection('incentives').doc();
        await ref.set({
          'title': 'Weekly 2', 'targetTrips': 2, 'windowDays': 7, 'bonusPaise': 30000,
          'startsAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))), 'active': true,
        });
        return ref.id;
      });
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: DriverRewardsScreen())));
      await settle(tester);
      expect(find.text('Weekly 2'), findsOneWidget);
      expect(find.text('2 of 2 trips done'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('claim_$id')));
      await settle(tester);
      expect(find.byKey(ValueKey('claimState_$id')), findsOneWidget);
      expect(find.text('Claimed: waiting for LoadGo to pay'), findsOneWidget);
    });
  });

  group('plans', () {
    test('Pro is active until planUntil', () {
      final now = DateTime(2026, 10, 4);
      expect(DriverPlan.isPro({'plan': 'pro'}, now), isTrue);
      expect(DriverPlan.isPro({'plan': 'pro', 'planUntil': Timestamp.fromDate(DateTime(2026, 11, 1))}, now), isTrue);
      expect(DriverPlan.isPro({'plan': 'pro', 'planUntil': Timestamp.fromDate(DateTime(2026, 9, 1))}, now), isFalse);
      expect(DriverPlan.isPro({'plan': 'free'}, now), isFalse);
      expect(DriverPlan.isPro(null, now), isFalse);
    });

    test('commission is lower on Pro and follows config', () {
      expect(PaymentService.commissionFor(100000), -5000);
      expect(PaymentService.commissionFor(100000, pro: true), -2000);
    });

    test('request, approve, and the commission line follows the plan', () async {
      await db.collection('users').doc('driver1').set({'role': 'driver'});
      await DriverExtrasService.requestPro();
      await expectLater(DriverExtrasService.requestPro(), throwsA(isA<ClaimException>()));
      await DriverExtrasService.setPlan('driver1', DriverPlan.pro, days: 30);
      final user = (await db.collection('users').doc('driver1').get()).data()!;
      expect(user['plan'], 'pro');
      expect((user['planUntil'] as Timestamp).toDate().isAfter(DateTime.now()), isTrue);
      expect((await db.collection('plan_requests').doc('driver1').get()).data()!['status'], 'approved');

      // a delivered, paid trip: the ledger commission is the Pro rate
      uid = 'customer1';
      final loadId = await LoadService.post(
          pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 1000,
          pickupDate: DateTime(2026, 10, 5), notes: '');
      uid = 'driver1';
      final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC1');
      final v = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == vid);
      final bid = await BookingService.accept(loadId: loadId, vehicle: v);
      await advanceTo(bid, BookingStatus.delivered);
      uid = 'customer1';
      var b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
      await PaymentService.markPaid(b, 100000);
      uid = 'driver1';
      b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
      await PaymentService.confirmReceived(b);
      expect((await db.collection('ledger').doc('${bid}_platform_commission').get()).data()!['amountPaise'], -2000);
    });

    test('free drivers pay the normal commission; rejecting a request keeps Free', () async {
      await db.collection('users').doc('driver1').set({'role': 'driver'});
      await DriverExtrasService.requestPro();
      await DriverExtrasService.rejectPlanRequest('driver1');
      expect((await db.collection('plan_requests').doc('driver1').get()).data()!['status'], 'rejected');
      expect((await db.collection('users').doc('driver1').get()).data()!.containsKey('plan'), isFalse);
      await DriverExtrasService.requestPro(); // can ask again
      expect((await db.collection('plan_requests').doc('driver1').get()).data()!['status'], 'pending');
    });

    testWidgets('driver screen: Free plan shows the request button, then the pending note', (tester) async {
      await tester.runAsync(() => db.collection('users').doc('driver1').set({'role': 'driver'}));
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: DriverRewardsScreen())));
      await settle(tester);
      expect(find.text('Free plan'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('requestPro')));
      await settle(tester);
      expect(find.byKey(const ValueKey('planPending')), findsOneWidget);
    });
  });

  testWidgets('admin screen: new incentive, claim paid, plan approval', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await db.collection('users').doc('d9').set({'role': 'driver'});
      await db.collection('plan_requests').doc('d9').set({'uid': 'd9', 'plan': 'pro', 'status': 'pending'});
      await db.collection('incentive_claims').doc('i_d9').set({
        'incentiveId': 'i', 'driverId': 'd9', 'bonusPaise': 40000, 'status': 'claimed', 'createdAt': Timestamp.now(),
      });
    });
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: AdminDriverRewardsScreen())));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('newIncentive')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('incTitle')), 'Diwali rush');
    await tester.tap(find.byType(ElevatedButton).last);
    await settle(tester);
    final inc = (await tester.runAsync(() => db.collection('incentives').get()))!.docs.single.data();
    expect(inc['title'], 'Diwali rush');
    expect(inc['targetTrips'], 10);
    expect(inc['bonusPaise'], 50000);

    await tester.tap(find.text('Claims'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('markPaid_i_d9')));
    await settle(tester);
    expect((await tester.runAsync(() => db.collection('incentive_claims').doc('i_d9').get()))!.data()!['status'], 'paid');

    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('approvePlan_d9')));
    await settle(tester);
    expect((await tester.runAsync(() => db.collection('users').doc('d9').get()))!.data()!['plan'], 'pro');
  });
}
