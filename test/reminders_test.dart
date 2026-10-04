import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/matching/city_demand.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/notifications/notifications_screen.dart';
import 'package:transport_app/core/reminders/reminders.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/reminder_service.dart';
import 'package:transport_app/core/widgets/reminder_widgets.dart';
import 'package:transport_app/driver/city_demand_screen.dart';

import 'test_utils.dart';

final day = DateTime(2026, 10, 8);

Future<Booking> booking(FakeFirebaseFirestore db, String id, {String status = 'accepted', String slot = 'morning', DateTime? date}) async {
  await db.collection('bookings').doc(id).set({
    'driverId': 'd1', 'customerId': 'c1', 'status': status, 'pickup': 'Delhi', 'drop': 'Jaipur',
    'pickupDate': Timestamp.fromDate(date ?? day), 'pickupSlot': slot, 'timeline': {},
  });
  return Booking.fromDoc(await db.collection('bookings').doc(id).get());
}

Future<Load> load(FakeFirebaseFirestore db, String id, String pickup, {String type = '14ft', String status = 'open', String slot = 'morning', String shipper = 'c1', DateTime? date}) async {
  await db.collection('loads').doc(id).set({
    'shipperId': shipper, 'pickup': pickup, 'drop': 'Jaipur', 'cargoType': 'FMCG', 'weight': 2, 'vehicleType': type,
    'pickupDate': Timestamp.fromDate(date ?? day), 'pickupSlot': slot, 'status': status,
  });
  return Load.fromDoc(await db.collection('loads').doc(id).get());
}

Future<Offer> offer(FakeFirebaseFirestore db, String id, String status) async {
  await db.collection('offers').doc(id).set({
    'loadId': 'L$id', 'driverId': 'd1', 'customerId': 'c1', 'status': status, 'pricePaise': 100000, 'originalPaise': 100000,
    'vehicleId': 'v', 'vehicleNumber': 'X', 'vehicleType': '14ft', 'driverName': 'R',
  });
  return Offer.fromDoc(await db.collection('offers').doc(id).get());
}

Vehicle vehicle({DateTime? insuranceExpiry, DateTime? service}) => Vehicle(
      id: 'v', ownerId: 'd1', number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'R', status: 'active',
      docs: {if (insuranceExpiry != null) 'insurance': VehicleDocInfo(expiry: insuranceExpiry)},
      nextServiceDate: service,
    );

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
    languageNotifier.value = AppLanguage.english;
  });

  List<ReminderKind> kinds(List<Reminder> l) => [for (final r in l) r.kind];

  group('pickup reminders', () {
    test('slot start hours', () {
      expect([for (final s in PickupSlot.all) PickupSlot.startHour(s)], [9, 8, 12, 15, 18]);
      expect(pickupMoment(DateTime(2026, 10, 8), 'evening'), DateTime(2026, 10, 8, 18));
    });

    test('shows from 1 hour before the slot until 2 hours after, with minutes left', () async {
      final b = await booking(db, 'b1');
      List<Reminder> at(DateTime now) => ReminderEngine.compute(ReminderInput(now: now, isDriver: true, bookings: [b]));
      expect(at(DateTime(2026, 10, 8, 6, 59)), isEmpty);
      final soon = at(DateTime(2026, 10, 8, 7, 15));
      expect(kinds(soon), [ReminderKind.pickupSoon]);
      expect(soon.single.args['minutes'], 45);
      expect(soon.single.relatedId, 'b1');
      expect(at(DateTime(2026, 10, 8, 8, 30)).single.args['minutes'], 0);
      expect(at(DateTime(2026, 10, 8, 10)), isNotEmpty);
      expect(at(DateTime(2026, 10, 8, 10, 1)), isEmpty);
    });

    test('only trips that have not left yet', () async {
      final list = [
        await booking(db, 'a'),
        await booking(db, 'b', status: 'picked_up'),
        await booking(db, 'c', status: 'delivered'),
        await booking(db, 'd', status: 'cancelled'),
      ];
      final r = ReminderEngine.compute(ReminderInput(now: DateTime(2026, 10, 8, 7, 30), isDriver: false, bookings: list));
      expect(r.map((x) => x.relatedId), ['a']);
    });

    test('customer: an open load with a pickup in the hour and no driver', () async {
      final l = await load(db, 'l1', 'Delhi');
      final matched = await load(db, 'l2', 'Delhi', status: 'matched');
      final r = ReminderEngine.compute(ReminderInput(now: DateTime(2026, 10, 8, 7, 30), isDriver: false, loads: [l, matched]));
      expect(kinds(r), [ReminderKind.noDriverYet]);
      expect(r.single.relatedId, 'l1');
      // a driver never gets that one
      expect(ReminderEngine.compute(ReminderInput(now: DateTime(2026, 10, 8, 7, 30), isDriver: true, loads: [l])), isEmpty);
    });
  });

  group('waiting answers', () {
    test('customer sees driver prices waiting; driver sees counters and selections', () async {
      final offers = [await offer(db, '1', 'pending'), await offer(db, '2', 'pending'), await offer(db, '3', 'countered'), await offer(db, '4', 'selected'), await offer(db, '5', 'rejected')];
      final now = DateTime(2026, 10, 8, 12);
      final customer = ReminderEngine.compute(ReminderInput(now: now, isDriver: false, offers: offers));
      expect(kinds(customer), [ReminderKind.offersWaiting]);
      expect(customer.single.args['n'], 2);
      final driver = ReminderEngine.compute(ReminderInput(now: now, isDriver: true, offers: offers));
      expect(kinds(driver), [ReminderKind.confirmWaiting, ReminderKind.counterWaiting]);
      expect(driver.first.args['n'], 1);
    });
  });

  group('driver papers', () {
    final now = DateTime(2026, 10, 8, 12);

    test('vehicle papers within 30 days (or expired) and service due', () {
      final r = ReminderEngine.compute(ReminderInput(
        now: now, isDriver: true,
        vehicles: [vehicle(insuranceExpiry: DateTime(2026, 10, 20), service: DateTime(2026, 10, 10)), vehicle(insuranceExpiry: DateTime(2027, 6, 1))],
      ));
      expect(kinds(r), [ReminderKind.vehicleDocs, ReminderKind.serviceDue]);
      expect(r.first.args['n'], 1);
    });

    test('licence: reminder in the last 30 days, urgent once expired, silent otherwise', () {
      List<Reminder> run(DateTime? expiry) => ReminderEngine.compute(ReminderInput(now: now, isDriver: true, licenceExpiry: expiry));
      expect(run(DateTime(2027, 1, 1)), isEmpty);
      expect(run(null), isEmpty);
      final soon = run(DateTime(2026, 10, 28));
      expect(soon.single.kind, ReminderKind.licenceExpiring);
      expect(soon.single.args, {'days': 20, 'expired': 0});
      final gone = run(DateTime(2026, 10, 1));
      expect(gone.single.args['expired'], 1);
      expect(gone.single.priority, 0);
      expect(run(DateTime(2026, 10, 8)).single.args['days'], 0, reason: 'expires today: still valid');
    });

    test('customers get no driver paper reminders', () {
      expect(ReminderEngine.compute(ReminderInput(now: now, isDriver: false, vehicles: [vehicle(insuranceExpiry: DateTime(2026, 10, 9))], licenceExpiry: DateTime(2026, 10, 9))), isEmpty);
    });

    test('most urgent first', () async {
      final b = await booking(db, 'b1', slot: 'midday');
      final r = ReminderEngine.compute(ReminderInput(
        now: DateTime(2026, 10, 8, 11, 30), isDriver: true, bookings: [b],
        vehicles: [vehicle(insuranceExpiry: DateTime(2026, 10, 9))], licenceExpiry: DateTime(2026, 10, 1),
      ));
      expect(r.map((x) => x.priority), [0, 0, 3]);
      expect(kinds(r).toSet(), {ReminderKind.pickupSoon, ReminderKind.licenceExpiring, ReminderKind.vehicleDocs});
    });
  });

  group('service', () {
    test('customer stream follows the data and the clock', () async {
      await booking(db, 'b1');
      var now = DateTime(2026, 10, 8, 5);
      final stream = ReminderService.watch(isDriver: false, clock: () => now);
      final seen = <List<Reminder>>[];
      final sub = stream.listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(seen.last, isEmpty);
      now = DateTime(2026, 10, 8, 7, 30);
      await db.collection('bookings').doc('b1').update({'notes': 'changed'}); // a change makes the stream recompute
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(kinds(seen.last), [ReminderKind.pickupSoon]);
      await sub.cancel();
    });

    test('driver stream reads the licence expiry from the profile', () async {
      Backend.useFakes(db: db, uid: () => 'd1');
      await db.collection('users').doc('d1').set({'driverKyc': {'dlExpiry': Timestamp.fromDate(DateTime(2026, 10, 20))}});
      final sub = ReminderService.watch(isDriver: true, clock: () => DateTime(2026, 10, 8)).listen((_) {});
      final first = await ReminderService.watch(isDriver: true, clock: () => DateTime(2026, 10, 8)).firstWhere((l) => l.isNotEmpty);
      expect(first.single.kind, ReminderKind.licenceExpiring);
      await sub.cancel();
    });
  });

  group('widgets', () {
    Widget app(Widget w) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
    const r1 = Reminder(kind: ReminderKind.pickupSoon, id: 'p1', args: {'route': 'Delhi → Jaipur', 'minutes': 40}, relatedId: 'b1', priority: 0);
    const r2 = Reminder(kind: ReminderKind.vehicleDocs, id: 'v', args: {'n': 2}, priority: 3);

    testWidgets('banner shows the most urgent reminders in words and opens one', (tester) async {
      Reminder? opened;
      await tester.pumpWidget(app(RemindersBanner(isDriver: true, source: Stream.value(const [r1, r2]), max: 1, onOpen: (r) => opened = r)));
      await tester.pump();
      expect(find.text('Pickup in 40 min: Delhi → Jaipur'), findsOneWidget);
      expect(find.textContaining('vehicle papers'), findsNothing);
      expect(find.text('+1 more reminders in Notifications'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reminder_p1')));
      expect(opened?.relatedId, 'b1');
    });

    testWidgets('banner is hidden with nothing to remind about', (tester) async {
      await tester.pumpWidget(app(RemindersBanner(isDriver: false, source: Stream.value(const []), onOpen: (_) {})));
      await tester.pump();
      expect(find.byType(ReminderTile), findsNothing);
    });

    testWidgets('every reminder kind has translated text', (tester) async {
      for (final lang in AppLanguage.values) {
        languageNotifier.value = lang;
        await tester.pumpWidget(app(Builder(builder: (context) {
          for (final k in ReminderKind.values) {
            final text = reminderText(context, Reminder(kind: k, id: 'x', args: const {'n': 1, 'days': 3, 'expired': 0, 'minutes': 5, 'route': 'A → B'}, priority: 0));
            expect(text.contains('{'), isFalse, reason: '${lang.name} $k');
          }
          return const SizedBox();
        })));
      }
    });

    testWidgets('notifications list shows reminders above the stored notifications', (tester) async {
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: NotificationsScreen(onOpenBooking: (_) {}, reminders: Stream.value(const [r1]))),
      ));
      await settle(tester);
      expect(find.text('Reminders'), findsOneWidget);
      expect(find.byKey(const ValueKey('notifReminder_p1')), findsOneWidget);
      expect(find.text('No notifications yet'), findsOneWidget);
    });
  });

  group('city demand', () {
    test('groups open loads by pickup city and vehicle type, busiest first, unknown places last', () async {
      final loads = [
        await load(db, '1', 'New Delhi', type: '14ft'),
        await load(db, '2', 'Delhi', type: '14ft'),
        await load(db, '3', 'Delhi', type: '20ft'),
        await load(db, '4', 'Mumbai', type: '20ft'),
        await load(db, '5', 'Some village', type: 'Mini'),
        await load(db, '6', 'Mumbai', type: '20ft', status: 'matched'),
        await load(db, '7', 'Pune', shipper: 'me'),
      ];
      final s = DemandSummary.from(loads, excludeShipperId: 'me');
      expect(s.totalLoads, 5);
      expect([for (final c in s.cities) c.city], ['Delhi', 'Mumbai', DemandSummary.otherLabel]);
      expect(s.cities.first.loads, 3);
      expect(s.cities.first.byType, {'14ft': 2, '20ft': 1});
      expect(s.cities.first.topType, '14ft');
      expect(s.byType.keys.first, '14ft'.compareTo('20ft') < 0 ? '14ft' : '20ft');
      expect(s.byType['20ft'], 2);
      expect(DemandSummary.from(const []).cities, isEmpty);
    });

    testWidgets('screen lists cities and types, highlights the driver\'s own', (tester) async {
      Backend.useFakes(db: db, uid: () => 'd1');
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final loads = (await tester.runAsync(() async => [await load(db, '1', 'Delhi'), await load(db, '2', 'Mumbai', type: '20ft')]))!;
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: CityDemandScreen(loads: Stream.value(loads)))));
      await settle(tester);
      expect(find.text('2 open loads right now'), findsOneWidget);
      expect(find.byKey(const ValueKey('city_Delhi')), findsOneWidget);
      expect(find.byKey(const ValueKey('city_Mumbai')), findsOneWidget);
      expect(find.byKey(const ValueKey('type_20ft')), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: CityDemandScreen(loads: Stream.value(const [])))));
      await settle(tester);
      expect(find.text('No open loads right now'), findsOneWidget);
    });
  });
}
