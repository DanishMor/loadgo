import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/adapters/connect_adapters.dart';
import 'package:transport_app/core/home/home_layout.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/driver/v3/driver_home_v3.dart';

final now = DateTime(2027, 5, 20, 15);
Booking trip(String id, String status, {DateTime? at}) => Booking.fromMap(id, {
      'status': status,
      'driverId': 'd1',
      'pickup': 'Pune',
      'drop': 'Surat',
      'budget': 2000,
      if (at != null) 'timeline': {'delivered': Timestamp.fromDate(at)},
    });
final _db = FakeFirebaseFirestore();
final _vehicles = <String, Vehicle>{};
final _offers = <String, Offer>{};
Vehicle truck(String id, {String docs = ''}) => _vehicles['$id$docs']!;
Offer bid(String id, String status) => _offers['$id$status']!;

Future<void> _fixtures() async {
  Future<void> v(String id, String tag, Map<String, Object?> docs) async {
    await _db.doc('vehicles/$id$tag').set({'ownerId': 'd1', 'number': 'MH12AB1234', 'type': '14ft', 'docs': docs});
    _vehicles['$id$tag'] = Vehicle.fromDoc(await _db.doc('vehicles/$id$tag').get());
  }

  await v('v1', '', {});
  await v('v1', 'expired', {'insurance': {'expiry': Timestamp.fromDate(DateTime(2027, 5, 1))}});
  await v('v1', 'soon', {'insurance': {'expiry': Timestamp.fromDate(DateTime(2027, 6, 1))}});
  for (final (id, status) in [('1', 'pending'), ('2', 'confirmed'), ('1', 'countered')]) {
    await _db.doc('offers/$id$status').set({'loadId': 'L$id', 'driverId': 'd1', 'pickup': 'Pune', 'drop': 'Nashik', 'pricePaise': 1500000, 'status': status});
    _offers['$id$status'] = Offer.fromDoc(await _db.doc('offers/$id$status').get());
  }
}

/// E22b: the v3 driver home built from sections.
void main() {
  setUpAll(_fixtures);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    languageNotifier.value = AppLanguage.english;
  });

  Widget host(Widget home, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
        notifier: ValueNotifier(lang),
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
            child: Directionality(textDirection: lang.textDirection, child: w!),
          ),
          home: Scaffold(body: home),
        ),
      );

  DriverHomeV3 home({
    Key? key,
    bool online = true,
    List<Vehicle> vehicles = const [],
    List<Booking> bookings = const [],
    Stream<List<Vehicle>>? vehicleStream,
    HomeLayout? layout,
    List<HomeLayout>? saved,
    List<int?>? goals,
    int? goal,
    List<String>? opened,
    List<Offer>? bids,
    List<DemandCell>? demand,
    ValueChanged<bool>? onOnline,
  }) =>
      DriverHomeV3(
        key: key,
        online: online,
        onOnline: onOnline ?? (_) {},
        vehicles: vehicleStream ?? Stream.value(vehicles),
        bookings: Stream.value(bookings),
        vehicleId: null,
        onVehicle: (_) {},
        onAddVehicle: () => opened?.add('addTruck'),
        onOpenLoads: () => opened?.add('loads'),
        onOpenBids: () => opened?.add('bids'),
        onOpenEarnings: () => opened?.add('earnings'),
        onOpenVehicles: () => opened?.add('vehicles'),
        header: const Text('Hello driver'),
        trips: const [Text('trip card', key: ValueKey('tripCard'))],
        more: const [Text('more tile', key: ValueKey('moreTile'))],
        returnLoads: (b) => Text('returns from ${b.drop}', key: const ValueKey('returnsWidget')),
        recentBids: bids == null ? null : () => Stream.value(bids),
        demand: demand == null ? null : () async => demand,
        loadLayout: () async => layout ?? DriverHomeSections.defaults,
        saveLayout: (l) async => saved?.add(l),
        loadGoal: () async => goal,
        saveGoal: (g) async => goals?.add(g),
        now: () => now,
      );

  Future<void> tall(WidgetTester t, {double width = 400}) async {
    t.view.physicalSize = Size(width, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('skeleton until the layout and both lists arrive, then the online hero', (t) async {
    await tall(t);
    final ctrl = StreamController<List<Vehicle>>();
    await t.pumpWidget(host(home(vehicleStream: ctrl.stream)));
    await t.pump();
    expect(find.byKey(const ValueKey('d3Skeleton')), findsOneWidget);
    ctrl.add([truck('v1')]);
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('d3Hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('d3Radar')), findsOneWidget);
    await ctrl.close();
  });

  testWidgets('switch, truck chips, papers, level and quick actions; no truck asks to add one', (t) async {
    await tall(t);
    final opened = <String>[];
    final flips = <bool>[];
    await t.pumpWidget(host(home(
      vehicles: [truck('v1', docs: 'expired')],
      bookings: [trip('a', 'delivered', at: DateTime(2027, 5, 20, 9)), trip('b', 'delivered', at: DateTime(2027, 5, 19, 9))],
      opened: opened,
      onOnline: flips.add,
    )));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('onlineSwitch')));
    expect(flips, [false]);
    expect(find.byType(ChoiceChip), findsOneWidget);
    expect(find.textContaining('expired'), findsOneWidget);
    expect(find.text('Starter'), findsOneWidget);
    expect(find.byKey(const ValueKey('d3Streak')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('d3QBids')));
    await t.tap(find.byKey(const ValueKey('d3Papers')));
    expect(opened, ['bids', 'vehicles']);

    await t.pumpWidget(host(home(key: const ValueKey(2), opened: opened)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('d3AddTruck')));
    expect(opened.last, 'addTruck');
    expect(find.byKey(const ValueKey('d3Papers')), findsNothing);
  });

  testWidgets("today's earnings fill the ring toward the driver's goal; a new goal is saved", (t) async {
    await tall(t);
    final goals = <int?>[];
    await t.pumpWidget(host(home(vehicles: [truck('v1')], bookings: [trip('a', 'delivered', at: DateTime(2027, 5, 20, 9))], goal: 4000, goals: goals)));
    await t.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('d3Ring')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('d3GoalField')), '2000');
    await t.tap(find.byKey(const ValueKey('d3GoalSave')));
    await t.pumpAndSettle();
    expect(goals, [2000]);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('return loads only with goods on board; demand only online and when the feed answers; recent bids', (t) async {
    await tall(t);
    final opened = <String>[];
    await t.pumpWidget(host(home(
      vehicles: [truck('v1')],
      bookings: [trip('a', 'in_transit')],
      bids: [bid('1', 'pending'), bid('2', 'confirmed')],
      demand: const [DemandCell('Vashi', 9)],
      opened: opened,
    )));
    await t.pumpAndSettle();
    expect(find.text('returns from Surat'), findsOneWidget);
    expect(find.text('Vashi: 9 loads'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Won'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('d3AllBids')));
    expect(opened, ['bids']);

    await t.pumpWidget(host(home(key: const ValueKey(2), online: false, vehicles: [truck('v1')], bookings: [trip('a', 'accepted')], bids: const [], demand: const [DemandCell('Vashi', 9)])));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('returnsWidget')), findsNothing);
    expect(find.byKey(const ValueKey('d3Demand')), findsNothing);
    expect(find.byKey(const ValueKey('d3Bids')), findsNothing);
  });

  testWidgets('saved layout is used; Arrange saves; the hero cannot be hidden', (t) async {
    await tall(t);
    final saved = <HomeLayout>[];
    final start = DriverHomeSections.defaults.toggle('more').toggle('hero');
    await t.pumpWidget(host(home(vehicles: [truck('v1')], layout: start, saved: saved)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('d3Hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('moreTile')), findsNothing);
    await t.tap(find.byKey(const ValueKey('d3Arrange')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('hlSwitch_level')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('hlDone')));
    await t.pumpAndSettle();
    expect(saved.single.isHidden('level'), isTrue);
    expect(find.byKey(const ValueKey('d3Level')), findsNothing);
  });

  testWidgets('a broken list shows an error with retry', (t) async {
    await tall(t);
    await t.pumpWidget(host(home(vehicleStream: Stream.error(StateError('x')))));
    await t.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, T.get('retry', AppLanguage.english)), findsOneWidget);
    expect(find.byKey(const ValueKey('d3Hero')), findsOneWidget);
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
      await tall(t, width: 320);
      await t.pumpWidget(host(
          home(
            vehicles: [truck('v1', docs: 'soon')],
            bookings: [trip('a', 'in_transit'), trip('b', 'delivered', at: DateTime(2027, 5, 20, 9))],
            bids: [bid('1', 'countered')],
            demand: const [DemandCell('Bhiwandi', 14)],
            goal: 3000,
          ),
          lang: lang,
          b: b,
          scale: 2));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('d3Hero')), findsOneWidget);
    });
  }
}
