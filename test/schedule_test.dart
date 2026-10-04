import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/matching/load_ranker.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/pricing/pricing_config.dart';
import 'package:transport_app/core/reminders/reminders.dart';
import 'package:transport_app/core/scheduling/schedule.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/notification_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/widgets/booking_list_view.dart';
import 'package:transport_app/customer/cancel_scheduled_button.dart';
import 'package:transport_app/driver/upcoming_trips.dart';

import 'test_utils.dart';

void main() {
  const rules = ScheduleRules();
  final now = DateTime(2026, 10, 8, 10);

  group('rules', () {
    test('limits: 1 hour to 30 days ahead', () {
      expect(Schedule.check(now.add(const Duration(minutes: 59)), now, rules), ScheduleProblem.tooSoon);
      expect(Schedule.check(now.add(const Duration(minutes: 60)), now, rules), isNull);
      expect(Schedule.check(now.add(const Duration(days: 30)), now, rules), isNull);
      expect(Schedule.check(now.add(const Duration(days: 31)), now, rules), ScheduleProblem.tooFar);
    });

    test('a booking is upcoming until one hour before its time, and only while it has not started', () {
      final at = now.add(const Duration(hours: 5));
      bool up(String status, DateTime n) => Schedule.isUpcoming(scheduledAt: at, status: status, now: n, r: rules);
      expect(up('accepted', now), isTrue);
      expect(up('accepted', at.subtract(const Duration(minutes: 61))), isTrue);
      expect(up('accepted', at.subtract(const Duration(minutes: 60))), isFalse, reason: 'active from the lead time');
      expect(up('driver_arriving', now), isFalse, reason: 'the driver already started');
      expect(Schedule.isUpcoming(scheduledAt: null, status: 'accepted', now: now, r: rules), isFalse);
      expect(Schedule.activatesAt(at, rules), at.subtract(const Duration(hours: 1)));
    });

    test('free cancel window and slots and countdown', () {
      final at = now.add(const Duration(hours: 5));
      expect(Schedule.freeToCancel(at, now.add(const Duration(hours: 3)), rules), isTrue);
      expect(Schedule.freeToCancel(at, now.add(const Duration(hours: 3, minutes: 1)), rules), isFalse);
      expect([for (final h in [8, 12, 15, 19]) Schedule.slotFor(DateTime(2026, 1, 1, h))], ['morning', 'midday', 'afternoon', 'evening']);
      final u = Schedule.until(now.add(const Duration(days: 2, hours: 3, minutes: 20)), now);
      expect((u.days, u.hours, u.minutes), (2, 3, 20));
      expect(Schedule.until(now.subtract(const Duration(hours: 1)), now).minutes, 0);
    });

    test('cancel charge: free before the window, the normal charge after', () {
      const policy = CancellationPolicy(scheduledFreeHours: 2, chargePercent: 10, minCharge: 5000, maxCharge: 100000);
      final at = DateTime(2026, 10, 10, 18);
      expect(policy.chargeForScheduled(now: at.subtract(const Duration(hours: 3)), scheduledAt: at, farePaise: 500000), 0);
      expect(policy.chargeForScheduled(now: at.subtract(const Duration(hours: 1)), scheduledAt: at, farePaise: 500000), 50000);
      expect(policy.chargeForScheduled(now: at.subtract(const Duration(hours: 1)), scheduledAt: at), 5000, reason: 'no estimate: the minimum');
    });

    test('config: defaults, overrides and the round trip', () {
      expect(defaultPricing.schedule.minMinutes, 60);
      final c = PricingConfig.fromMap({
        'schedule': {'minMinutes': 90, 'maxDays': 10, 'leadMinutes': 30},
        'cancellation': {'scheduledFreeHours': 4},
      });
      expect((c.schedule.minMinutes, c.schedule.maxDays, c.schedule.leadMinutes, c.schedule.freeCancelHours), (90, 10, 30, 4));
      expect(c.cancellation.scheduledFreeHours, 4);
      final back = PricingConfig.fromMap(Map<String, dynamic>.from(c.toMap()));
      expect(back.schedule.maxDays, 10);
      expect(back.cancellation.scheduledFreeHours, 4);
    });
  });

  group('services', () {
    late FakeFirebaseFirestore db;
    String uid = 'c1';
    setUp(() {
      db = FakeFirebaseFirestore();
      uid = 'c1';
      Backend.useFakes(db: db, uid: () => uid);
      PricingService.reset();
      languageNotifier.value = AppLanguage.english;
    });

    Future<String> post(DateTime? at, {DateTime? date}) => LoadService.post(
          pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null,
          pickupDate: date ?? DateTime.now(), notes: '', scheduledAt: at,
        );

    test('posting stores the time, sets the date and slot from it, and refuses bad times', () async {
      final at = DateTime.now().add(const Duration(days: 3, hours: 2));
      final id = await post(at, date: DateTime(2020));
      final l = Load.fromDoc(await db.collection('loads').doc(id).get());
      expect(l.scheduledAt!.difference(at).abs().inSeconds, lessThan(2));
      expect(l.pickupDate, DateTime(at.year, at.month, at.day));
      expect(l.pickupSlot, Schedule.slotFor(at));
      await expectLater(post(DateTime.now().add(const Duration(minutes: 10))), throwsA(isA<ScheduleException>().having((e) => e.problem, 'problem', ScheduleProblem.tooSoon)));
      await expectLater(post(DateTime.now().add(const Duration(days: 40))), throwsA(isA<ScheduleException>().having((e) => e.problem, 'problem', ScheduleProblem.tooFar)));
      expect(Load.fromDoc(await db.collection('loads').doc(await post(null)).get()).scheduledAt, isNull);
    });

    Future<({String loadId, String vehicleId, Vehicle vehicle})> setup(DateTime? at) async {
      uid = 'c1';
      final loadId = await post(at);
      uid = 'd1';
      final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC1');
      final v = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == vid);
      return (loadId: loadId, vehicleId: vid, vehicle: v);
    }

    Future<String> availability(String vid) async => (await db.collection('vehicles').doc(vid).get()).data()!['availability'] as String;

    test('accepting an advance booking copies the time and keeps the vehicle free until the driver starts', () async {
      final at = DateTime.now().add(const Duration(days: 2));
      final s = await setup(at);
      final bid = await BookingService.accept(loadId: s.loadId, vehicle: s.vehicle);
      var b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
      expect(b.scheduledAt!.difference(at).abs().inSeconds, lessThan(2));
      expect(await availability(s.vehicleId), 'available');
      expect(b.isUpcoming(DateTime.now(), PricingService.config.schedule), isTrue);

      await BookingService.advance(bid); // driver_arriving: the trip starts, the vehicle becomes busy
      expect(await availability(s.vehicleId), 'on_trip');
      b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
      expect(b.status, 'driver_arriving');
      expect(b.isUpcoming(DateTime.now(), PricingService.config.schedule), isFalse);
    });

    test('a load due within the lead time busies the vehicle straight away', () async {
      PricingService.notifier.value = PricingConfig.fromMap({'schedule': {'minMinutes': 10, 'leadMinutes': 60}});
      final s = await setup(DateTime.now().add(const Duration(minutes: 30)));
      await BookingService.accept(loadId: s.loadId, vehicle: s.vehicle);
      expect(await availability(s.vehicleId), 'on_trip');
    });

    test('more than the lead time away leaves it free', () async {
      final s = await setup(DateTime.now().add(const Duration(minutes: 90)));
      await BookingService.accept(loadId: s.loadId, vehicle: s.vehicle);
      expect(await availability(s.vehicleId), 'available');
    });

    test('a normal booking still busies the vehicle at once', () async {
      final s = await setup(null);
      await BookingService.accept(loadId: s.loadId, vehicle: s.vehicle);
      expect(await availability(s.vehicleId), 'on_trip');
    });

    test('two advance bookings within 12 hours on one vehicle clash; a far one does not', () async {
      final at = DateTime.now().add(const Duration(days: 2));
      final s = await setup(at);
      await BookingService.accept(loadId: s.loadId, vehicle: s.vehicle);
      uid = 'c1';
      final near = await post(at.add(const Duration(hours: 6)));
      final far = await post(at.add(const Duration(hours: 30)));
      uid = 'd1';
      await expectLater(BookingService.accept(loadId: near, vehicle: s.vehicle), throwsA(isA<VehicleBusyException>()));
      await BookingService.accept(loadId: far, vehicle: s.vehicle);
    });

    test('the customer cancels an advance booking: free early, charged late; load closed; driver told', () async {
      final at = DateTime.now().add(const Duration(days: 2));
      final s = await setup(at);
      final bid = await BookingService.accept(loadId: s.loadId, vehicle: s.vehicle);
      uid = 'c1';
      final charge = await BookingService.cancelScheduledByCustomer(bid);
      expect(charge, 0);
      final b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
      expect(b.status, 'cancelled');
      expect(b.cancellation!.by, 'customer');
      final l = Load.fromDoc(await db.collection('loads').doc(s.loadId).get());
      expect(l.status, 'closed');
      expect(l.cancelled, isTrue);
      expect((await db.collection('users').doc('c1').get()).data()!['cancelCount'], 1);
      uid = 'd1';
      expect((await NotificationService.watchMine().first).any((n) => n.type == 'booking_cancelled'), isTrue);
      expect(await availability(s.vehicleId), 'available');
    });

    test('cancelling inside the window records the policy charge', () async {
      final at = DateTime.now().add(const Duration(days: 2));
      final s = await setup(at);
      await db.collection('loads').doc(s.loadId).update({'estimate': {'baseFare': 300000, 'distanceKm': 100}});
      final bid = await BookingService.accept(loadId: s.loadId, vehicle: s.vehicle);
      uid = 'c1';
      final charge = await BookingService.cancelScheduledByCustomer(bid, now: at.subtract(const Duration(minutes: 30)));
      expect(charge, 30000);
      expect(Booking.fromDoc(await db.collection('bookings').doc(bid).get()).cancellation!.chargePaise, 30000);
    });

    test('only the customer, only for advance bookings that have not started', () async {
      final s = await setup(DateTime.now().add(const Duration(days: 2)));
      final bid = await BookingService.accept(loadId: s.loadId, vehicle: s.vehicle);
      uid = 'someoneElse';
      await expectLater(BookingService.cancelScheduledByCustomer(bid), throwsStateError);
      uid = 'd1';
      await BookingService.advance(bid);
      uid = 'c1';
      await expectLater(BookingService.cancelScheduledByCustomer(bid), throwsStateError);
      final plain = await post(null);
      uid = 'd2';
      final vid2 = await VehicleService.add(number: 'MH12AB9999', type: '14ft', capacity: 4, rcNumber: 'RC2');
      final v2 = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == vid2);
      final nb = await BookingService.accept(loadId: plain, vehicle: v2);
      uid = 'c1';
      await expectLater(BookingService.cancelScheduledByCustomer(nb), throwsStateError, reason: 'not an advance booking');
    });

    testWidgets('driver: upcoming card and list with countdown; the active card hides upcoming trips', (tester) async {
      final at = DateTime.now().add(const Duration(days: 2, hours: 3));
      final s = (await tester.runAsync(() => setup(at)))!;
      await tester.runAsync(() => BookingService.accept(loadId: s.loadId, vehicle: s.vehicle));
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: Scaffold(body: Column(children: [
          UpcomingTripsCard(onOpen: (_) {}),
          Expanded(child: ActiveTripCard(bookings: BookingService.watchForDriver, onOpen: (_) {}, empty: const Text('NO ACTIVE'))),
        ]))),
      ));
      await settle(tester);
      expect(find.byKey(const ValueKey('upcomingCard')), findsOneWidget);
      expect(find.textContaining('1 upcoming trip'), findsOneWidget);
      expect(find.text('NO ACTIVE'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('upcomingCard')));
      await settle(tester);
      expect(find.textContaining('Starts in 2 d'), findsWidgets);
    });

    testWidgets('customer: the cancel button explains the charge and cancels', (tester) async {
      final at = DateTime.now().add(const Duration(days: 2));
      final s = (await tester.runAsync(() => setup(at)))!;
      final bid = (await tester.runAsync(() => BookingService.accept(loadId: s.loadId, vehicle: s.vehicle)))!;
      uid = 'c1';
      final b = (await tester.runAsync(() async => Booking.fromDoc(await db.collection('bookings').doc(bid).get())))!;
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: CancelScheduledButton(booking: b)))));
      await tester.tap(find.byKey(const ValueKey('cancelScheduled')));
      await tester.pumpAndSettle();
      expect(find.text('Cancelling is free until 2 hours before the pickup time.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancelScheduledConfirm')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('bookings').doc(bid).get()))!.data()!['status'], 'cancelled');
    });
  });

  group('reminders and matching use the exact time', () {
    test('the pickup reminder follows scheduledAt, not the slot', () {
      final b = Booking(
        id: 'b', loadId: 'l', driverId: 'd', vehicleId: 'v', customerId: 'c', status: 'accepted', pickup: 'A', drop: 'B', cargoType: 'x',
        weight: 1, vehicleType: '14ft', budget: null, pickupDate: DateTime(2026, 10, 8), notes: '', vehicleNumber: 'X', driverName: 'D',
        driverPhone: '1', timeline: const {}, scheduledAt: DateTime(2026, 10, 8, 16, 30),
      );
      List<Reminder> at(DateTime t) => ReminderEngine.compute(ReminderInput(now: t, isDriver: true, bookings: [b]));
      expect(at(DateTime(2026, 10, 8, 8, 30)), isEmpty, reason: 'the any-time slot would have fired at 8');
      expect(at(DateTime(2026, 10, 8, 15, 40)).single.args['minutes'], 50);
    });

    test('a busy vehicle can take a load scheduled more than a day ahead (SM10)', () {
      final busy = Vehicle(id: 'v', ownerId: 'd', number: 'X', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active', availability: VehicleAvailability.onTrip);
      Load l(DateTime? at) => Load(
            id: 'l', shipperId: 'c', pickup: 'Delhi', drop: 'Mumbai', cargoType: 'x', weight: 5, vehicleType: '20ft', budget: 1,
            pickupDate: null, notes: '', status: 'open', scheduledAt: at,
          );
      final ctx = DriverContext(vehicles: [busy], now: now);
      expect(LoadRanker.matchFor(l(null), ctx), isNull);
      expect(LoadRanker.matchFor(l(now.add(const Duration(hours: 5))), ctx), isNull);
      expect(LoadRanker.matchFor(l(now.add(const Duration(hours: 30))), ctx), isNotNull);
    });
  });
}
