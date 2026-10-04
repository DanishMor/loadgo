import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/constants/prohibited_cargo.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/saved_place.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/services/saved_place_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/share_text.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/customer/my_loads_view.dart';
import 'package:transport_app/customer/post_load_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'customer1';
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });

  Future<String> post({
    List<String> extraPickups = const [],
    List<String> extraDrops = const [],
    String notes = '',
    String slot = PickupSlot.any,
  }) =>
      LoadService.post(
        pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null,
        pickupDate: DateTime(2026, 10, 5), notes: notes, extraPickups: extraPickups, extraDrops: extraDrops, pickupSlot: slot,
      );

  group('prohibited cargo', () {
    test('matches whole words, case-insensitive', () {
      expect(prohibitedCargoMatch('Box of EXPLOSIVES'), 'explosives');
      expect(prohibitedCargoMatch('diwali crackers 20 boxes'), 'crackers');
      expect(prohibitedCargoMatch('fake currency notes'), 'fake currency');
      expect(prohibitedCargoMatch('Gunny bags of rice'), isNull, reason: '"gun" only as a word');
      expect(prohibitedCargoMatch('Drugstore shelves'), isNull);
      expect(prohibitedCargoMatch(''), isNull);
    });

    test('posting refuses prohibited notes', () async {
      await expectLater(post(notes: 'pistol parts'), throwsA(isA<ProhibitedCargoException>()));
      expect((await db.collection('loads').get()).docs, isEmpty);
    });
  });

  test('multi-stop: extras stored in order, capped at 2 per side; booking copies them', () async {
    final id = await post(extraPickups: ['Gurugram', ' ', 'Noida', 'Agra'], extraDrops: ['Ajmer'], slot: PickupSlot.morning);
    final load = Load.fromDoc(await db.collection('loads').doc(id).get());
    expect(load.extraPickups, ['Gurugram', 'Noida']);
    expect(load.extraDrops, ['Ajmer']);
    expect(load.route, ['Delhi', 'Gurugram', 'Noida', 'Ajmer', 'Jaipur']);
    expect(load.extraStopCount, 3);
    expect(load.pickupSlot, PickupSlot.morning);
    expect(loadShareText(load), contains('Delhi -> Gurugram -> Noida -> Ajmer -> Jaipur'));

    uid = 'driver1';
    final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC1');
    final v = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == vid);
    final bookingId = await BookingService.accept(loadId: id, vehicle: v);
    final b = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect(b.route, load.route);
    expect(b.pickupSlot, PickupSlot.morning);
  });

  test('route distance sums every leg and extra stops raise the quote', () {
    final direct = PricingService.estimateRouteKm(['Delhi', 'Jaipur'])!;
    final viaAgra = PricingService.estimateRouteKm(['Delhi', 'Agra', 'Jaipur'])!;
    expect(viaAgra, greaterThan(direct));
    expect(PricingService.estimateRouteKm(['Delhi', 'Atlantis', 'Jaipur']), isNull);
    final plain = PricingService.quote(vehicleType: '14ft', distanceKm: 300);
    final stops = PricingService.quote(vehicleType: '14ft', distanceKm: 300, extraStops: 2);
    expect(stops.total, greaterThan(plain.total));
  });

  test('saved places: add, list sorted, delete, limit', () async {
    await SavedPlaceService.add(label: PlaceLabel.warehouse, name: 'Bhiwandi WH', address: 'Bhiwandi, Thane');
    await SavedPlaceService.add(label: PlaceLabel.port, name: 'JNPT', address: 'Nhava Sheva');
    final places = await SavedPlaceService.watchMine().first;
    expect(places.map((p) => p.name), ['Bhiwandi WH', 'JNPT']);
    await SavedPlaceService.delete(places.first.id);
    expect((await SavedPlaceService.watchMine().first).single.name, 'JNPT');
    for (var i = 0; i < SavedPlaceService.maxPlaces - 1; i++) {
      await SavedPlaceService.add(label: PlaceLabel.home, name: 'P$i', address: 'Addr');
    }
    await expectLater(SavedPlaceService.add(label: PlaceLabel.home, name: 'X', address: 'Addr'), throwsA(isA<TooManyPlacesException>()));
  });

  Future<void> pumpForm(WidgetTester tester, Widget screen) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(navigatorKey: nav, home: const Scaffold()),
    ));
    nav.currentState!.push(MaterialPageRoute(builder: (_) => screen));
    await tester.pumpAndSettle();
  }

  testWidgets('form: add a pickup stop, pick a saved place, block prohibited notes', (tester) async {
    await tester.runAsync(() => SavedPlaceService.add(label: PlaceLabel.warehouse, name: 'Agra WH', address: 'Agra'));
    await pumpForm(tester, const PostLoadScreen());

    await tester.enterText(find.byType(TextFormField).at(0), 'Delhi');
    await tester.enterText(find.byType(TextFormField).at(1), 'Jaipur');
    await tester.tap(find.byKey(const ValueKey('addPickupStop')));
    await tester.pumpAndSettle();
    expect(find.text('Pickup 2'), findsOneWidget);

    // Fill the new stop from saved places (second bookmark icon = the stop).
    await tester.tap(find.byIcon(Icons.bookmark_border_rounded).at(1));
    await settle(tester);
    await tester.tap(find.text('Agra WH'));
    await tester.pumpAndSettle();
    expect(find.text('Agra WH, Agra'), findsOneWidget);
    // Two pickups -> one extra stop is quoted.
    expect(find.byKey(const ValueKey('fareTotal')), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(3), '2');
    final notes = find.byType(TextFormField).last;
    await tester.enterText(notes, 'some ammunition');
    await tester.ensureVisible(find.byType(PrimaryButton));
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('LoadGo cannot carry "ammunition"'), findsOneWidget);
    expect((await tester.runAsync(() => db.collection('loads').get()))!.docs, isEmpty);
  });

  testWidgets('repost prefills everything except the date', (tester) async {
    final id = await tester.runAsync(() => post(extraDrops: ['Ajmer'], slot: PickupSlot.evening));
    await tester.runAsync(() => db.collection('loads').doc(id).update({'status': LoadStatus.closed}));
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: MyLoadsView(onPostLoad: () {}, onOpenBooking: (_) {}))),
    ));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('repost_$id')));
    await tester.pumpAndSettle();
    expect(find.byType(PostLoadScreen), findsOneWidget);
    expect(find.text('Delhi'), findsOneWidget);
    expect(find.text('Ajmer'), findsOneWidget);
    expect(find.text('Evening (6–10 PM)'), findsOneWidget);
    expect(find.text('--'), findsOneWidget, reason: 'pickup date must be chosen again');
  });
}
