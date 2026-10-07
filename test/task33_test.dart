import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/lifecycle.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/recurring.dart';
import 'package:transport_app/core/models/repeat.dart';
import 'package:transport_app/core/pricing/cities.dart';
import 'package:transport_app/core/search/text_search.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/recurring_service.dart';
import 'package:transport_app/core/services/repeat_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/trip/arrival_eta.dart';
import 'package:transport_app/core/widgets/lifecycle_bar.dart';
import 'package:transport_app/core/widgets/trip_eta_card.dart';
import 'package:transport_app/core/search/global_search_screen.dart';
import 'package:transport_app/customer/place_field.dart';
import 'package:transport_app/customer/recurring_due_card.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth current;
  final people = <String, MockFirebaseAuth>{};
  void signIn(String uid, String phone) =>
      current = people.putIfAbsent(uid, () => MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid, phoneNumber: phone)));

  setUp(() {
    db = FakeFirebaseFirestore();
    people.clear();
    signIn('c1', '+919800000001');
    Backend.useFakes(db: db, uid: () => current.currentUser?.uid, auth: () => current);
    languageNotifier.value = AppLanguage.english;
  });

  Map<String, Object?> bookingMap({String status = 'accepted', String pickup = 'Pune', GeoPoint? at, String payment = 'pending'}) => {
        'customerId': 'c1', 'driverId': 'd1', 'status': status, 'agreedFarePaise': 100000, 'pickup': pickup, 'drop': 'Delhi',
        'loadId': 'L', 'vehicleId': 'v', 'cargoType': 'FMCG', 'weight': 5, 'vehicleType': '20ft', 'notes': '', 'vehicleNumber': 'MH12AB1234',
        'driverName': 'Ravi', 'driverPhone': '1', 'timeline': <String, Object?>{}, 'paymentStatus': payment, 'lastKnownLocation': at,
      };

  Future<Booking> booking(Map<String, Object?> m) async {
    final ref = await db.collection('bookings').add(m);
    return Booking.fromDoc(await ref.get());
  }

  group('place suggestions and my location (M1, M2)', () {
    test('prefix matches come first, aliases work, empty gives nothing', () {
      expect(suggestCities('del').first.name, 'Delhi');
      expect(suggestCities('bangal').single.name, 'Bengaluru');
      expect(suggestCities('  '), isEmpty);
      expect(suggestCities('mum').first.name, 'Mumbai');
      expect(suggestCities('a', limit: 3).length, lessThanOrEqualTo(3));
    });

    test('nearest city of a position, null when far from every city', () {
      expect(nearestCity(28.62, 77.21)?.name, 'Delhi');
      expect(nearestCity(18.53, 73.85)?.name, 'Pune');
      expect(nearestCity(0, 0), isNull);
    });

    testWidgets('typing shows city suggestions and a tap fills the field', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: PlaceField(controller: c, icon: const Icon(Icons.place), myLocation: true))),
      ));
      await tester.enterText(find.byType(TextFormField), 'pun');
      await settle(tester);
      expect(find.byKey(const ValueKey('city_Pune')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('city_Pune')));
      await settle(tester);
      expect(c.text, 'Pune');
      expect(find.byKey(const ValueKey('useMyLocation')), findsOneWidget);
    });
  });

  group('home search (C1)', () {
    test('every typed word must start a word of some field', () {
      expect(matchesQuery('del mum', ['Delhi', 'Mumbai']), isTrue);
      expect(matchesQuery('del chen', ['Delhi', 'Mumbai']), isFalse);
      expect(matchesQuery('', ['Delhi']), isFalse);
      expect(matchesQuery('fmcg', ['FMCG goods', null]), isTrue);
    });

    testWidgets('finds my loads and bookings and says so when nothing matches', (tester) async {
      await db.collection('loads').doc('L1').set({'shipperId': 'c1', 'pickup': 'Delhi', 'drop': 'Mumbai', 'cargoType': 'FMCG', 'weight': 5, 'vehicleType': '20ft', 'status': 'open', 'notes': '', 'pickupDate': Timestamp.now()});
      final b = await booking(bookingMap(pickup: 'Pune'));
      await tester.pumpWidget(MaterialApp(
        home: GlobalSearchScreen(
          isDriver: false,
          debounce: Duration.zero,
          loads: Stream.value([Load.fromDoc(await db.collection('loads').doc('L1').get())]),
          bookings: Stream.value([b]),
          tickets: Stream.value(const []),
          places: Stream.value(const []),
        ),
      ));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('globalSearchField')), 'del mum');
      await settle(tester);
      expect(find.byKey(const ValueKey('hit_load_L1')), findsOneWidget);
      expect(find.byKey(ValueKey('hit_booking_${b.id}')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('globalSearchField')), 'ravi');
      await settle(tester);
      expect(find.byKey(ValueKey('hit_booking_${b.id}')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('globalSearchField')), 'zzz');
      await settle(tester);
      expect(find.text('Nothing found for "zzz"'), findsOneWidget);
    });
  });

  group('shipment lifecycle (P12)', () {
    test('derived from load, offer and booking', () async {
      expect(lifecycleOf(), LifecycleStage.created);
      expect(lifecycleOf(hasOfferSelected: true), LifecycleStage.matched);
      expect(lifecycleOf(booking: await booking(bookingMap())), LifecycleStage.confirmed);
      expect(lifecycleOf(booking: await booking(bookingMap(status: 'picked_up'))), LifecycleStage.pickedUp);
      expect(lifecycleOf(booking: await booking(bookingMap(status: 'unloading'))), LifecycleStage.inTransit);
      expect(lifecycleOf(booking: await booking(bookingMap(status: 'delivered'))), LifecycleStage.delivered);
      expect(lifecycleOf(booking: await booking(bookingMap(status: 'delivered', payment: 'driver_confirmed'))), LifecycleStage.settled);
      expect(lifecycleOf(booking: await booking(bookingMap(status: 'cancelled'))), LifecycleStage.cancelled);
    });

    testWidgets('the bar marks the current step', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LifecycleBar(stage: LifecycleStage.inTransit))));
      await settle(tester);
      expect(find.byKey(const ValueKey('lc_inTransit')), findsOneWidget);
      expect(find.text('On the way'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LifecycleBar(stage: LifecycleStage.cancelled))));
      await settle(tester);
      expect(find.text('Cancelled'), findsOneWidget);
    });
  });

  group('driver arriving ETA (T2, C10)', () {
    final pune = indianCities.firstWhere((c) => c.name == 'Pune');

    test('km and time from the shared position; arrived within 2 km; nothing without a position or after pickup', () async {
      final far = await booking(bookingMap(status: 'driver_arriving', at: const GeoPoint(19.0760, 72.8777))); // Mumbai
      final eta = ArrivalEta.of(far, now: DateTime(2026, 10, 6, 10))!;
      expect(eta.km, inInclusiveRange(150, 190));
      expect(eta.time.inMinutes, greaterThan(200));
      expect(eta.arrived, isFalse);
      final near = await booking(bookingMap(status: 'driver_arriving', at: GeoPoint(pune.lat + 0.005, pune.lng)));
      expect(ArrivalEta.of(near)!.arrived, isTrue);
      expect(ArrivalEta.of(await booking(bookingMap(status: 'driver_arriving'))), isNull);
      expect(ArrivalEta.of(await booking(bookingMap(status: 'in_transit', at: const GeoPoint(19, 72)))), isNull);
      expect(ArrivalEta.of(await booking(bookingMap(status: 'driver_arriving', pickup: 'Nowhereville', at: const GeoPoint(19, 72)))), isNull);
    });

    testWidgets('the card shows the line', (tester) async {
      final far = await booking(bookingMap(status: 'driver_arriving', at: const GeoPoint(19.0760, 72.8777)));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ArrivalEtaCard(booking: far))));
      await settle(tester);
      expect(find.textContaining('Driver is about'), findsOneWidget);
    });

    test('the driver may share a position while on the way to the pickup', () async {
      signIn('d1', '+919811111111');
      final b = await booking(bookingMap(status: 'driver_arriving'));
      await BookingService.updateLocation(b.id, 18.6, 73.9);
      expect((await db.collection('bookings').doc(b.id).get())['lastKnownLocation'], isNotNull);
      final loading = await booking(bookingMap(status: 'loading'));
      await BookingService.updateLocation(loading.id, 18.6, 73.9);
      expect((await db.collection('bookings').doc(loading.id).get()).data()!['lastKnownLocation'], isNull);
    });
  });

  group('repeating loads (P3)', () {
    test('next date: a week later, or the same day next month clamped to the month end', () {
      expect(Frequency.next(DateTime(2026, 10, 6, 9), Frequency.weekly), DateTime(2026, 10, 13, 9));
      expect(Frequency.next(DateTime(2026, 1, 31), Frequency.monthly), DateTime(2026, 2, 28));
      expect(Frequency.next(DateTime(2026, 12, 15), Frequency.monthly), DateTime(2027, 1, 15));
    });

    LoadTemplate t() => const LoadTemplate(id: '', name: 'Pune - Delhi', pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 8, vehicleType: '20ft');

    test('create, due, advance past today, stop, and the 10 limit', () async {
      await RecurringService.create(t(), Frequency.weekly, first: DateTime(2026, 10, 6));
      var list = await RecurringService.watch().first;
      expect(list.single.nextDueAt, DateTime(2026, 10, 13));
      expect(list.single.isDue(DateTime(2026, 10, 12)), isFalse);
      expect(list.single.isDue(DateTime(2026, 10, 13, 8)), isTrue);
      expect(list.single.toDraft().pickup, 'Pune');
      // away for a month: the next date moves past today
      await RecurringService.advance(list.single, now: DateTime(2026, 11, 20));
      list = await RecurringService.watch().first;
      expect(list.single.nextDueAt.isAfter(DateTime(2026, 11, 20)), isTrue);
      await RecurringService.setActive(list.single.id, false);
      expect((await RecurringService.watch().first).single.isDue(DateTime(2030)), isFalse);
      await RecurringService.delete(list.single.id);
      for (var i = 0; i < RecurringLoad.maxPerUser; i++) {
        await RecurringService.create(t(), Frequency.monthly, first: DateTime(2026, 10, 6));
      }
      await expectLater(RecurringService.create(t(), Frequency.monthly, first: DateTime(2026, 10, 6)), throwsA(isA<RecurringLimitException>()));
      expect(() => RecurringService.create(t(), 'daily', first: DateTime(2026, 10, 6)), throwsArgumentError);
    });

    testWidgets('a due load shows Post now / Skip / Stop and skipping hides it', (tester) async {
      await RecurringService.create(t(), Frequency.weekly, first: DateTime(2026, 10, 6));
      final id = (await RecurringService.watch().first).single.id;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecurringDueCard(clock: () => DateTime(2026, 10, 14)))));
      await settle(tester);
      expect(find.byKey(ValueKey('recurringDue_$id')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('recurringSkip_$id')));
      await settle(tester);
      expect(find.byKey(ValueKey('recurringDue_$id')), findsNothing);
    });
  });

  group('load visibility and pickup now (L13, B7)', () {
    Future<String> post({String visibility = 'public', List<String> allowed = const [], bool instant = false}) => LoadService.post(
          pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: 20000,
          pickupDate: DateTime.now().add(const Duration(days: 1)), notes: '',
          visibility: visibility, allowedDriverIds: allowed, instant: instant,
        );

    setUp(() async {
      await db.collection('users').doc('c1').set({'role': 'customer', 'name': 'C'});
    });

    test('a favourites load is hidden from other drivers and refused at accept; instant is stored', () async {
      await RepeatService.addFavourite(driverId: 'good', name: 'Good');
      final fav = await RepeatService.favouriteIds();
      expect(fav, ['good']);
      final id = await post(visibility: 'favourites', allowed: fav, instant: true);
      final load = Load.fromDoc(await db.collection('loads').doc(id).get());
      expect(load.visibility, 'favourites');
      expect(load.allowedDriverIds, ['good']);
      expect(load.instant, isTrue);
      expect(load.blocks('good'), isFalse);
      expect(load.blocks('other'), isTrue);

      await db.collection('users').doc('other').set({'role': 'driver', 'driverName': 'O', 'phone': '+919822222222', 'verified': true});
      signIn('other', '+919822222222');
      expect(await LoadService.watchOpen().first, isEmpty);
      final v = await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
      final vehicle = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == v);
      await expectLater(BookingService.accept(loadId: id, vehicle: vehicle), throwsA(isA<LoadUnavailableException>()));

      await db.collection('users').doc('good').set({'role': 'driver', 'driverName': 'G', 'phone': '+919833333333', 'verified': true});
      signIn('good', '+919833333333');
      expect((await LoadService.watchOpen().first).single.id, id);
    });

    test('a public load needs no list; a restricted one needs 1 to 20 drivers; unknown values are refused', () async {
      expect((await db.collection('loads').doc(await post()).get()).data()!.containsKey('visibility'), isFalse);
      await expectLater(post(visibility: 'favourites'), throwsArgumentError);
      await expectLater(post(visibility: 'invite', allowed: List.generate(21, (i) => 'd$i')), throwsArgumentError);
      await expectLater(post(visibility: 'secret', allowed: ['x']), throwsArgumentError);
    });
  });
}
