import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/home/home_layout.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/offers/offers_switch.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/offers_switch_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/vehicles/vehicle_catalog.dart';
import 'package:transport_app/customer/v2/booking_wizard_model.dart';
import 'package:transport_app/customer/v3/customer_home_v3.dart';

Booking booking(String id, String status) => Booking.fromMap(id, {'pickup': 'Delhi', 'drop': 'Jaipur', 'status': status, 'customerId': 'cust1', 'driverId': 'd1', 'loadId': 'L$id'});
Load load(String id, String status, {String pickup = 'Delhi', String drop = 'Jaipur'}) =>
    Load(id: id, shipperId: 'cust1', pickup: pickup, drop: drop, cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null, pickupDate: DateTime(2030), notes: '', status: status);

/// E21b: the v3 customer home built from sections (order and hidden kept on the phone).
void main() {
  late List<VehicleSpec> specs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'cust1', phoneNumber: '+919800000001'));
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'cust1', auth: () => auth);
    FeaturesService.reset();
    OffersSwitchService.notifier.value = const OffersSwitch();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(() {
    FeaturesService.reset();
    OffersSwitchService.notifier.value = const OffersSwitch();
  });

  String en(String k) => T.get(k, AppLanguage.english);

  Widget host(Widget home, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
        notifier: ValueNotifier(lang),
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: lang.textDirection, child: w!)),
          home: Scaffold(body: home),
        ),
      );

  CustomerHomeV3 home({
    Key? key,
    List<Booking> bookings = const [],
    List<Load> loads = const [],
    Stream<List<Booking>> Function()? bookingStream,
    HomeLayout? layout,
    List<HomeLayout>? saved,
    List<WizardDraft>? drafts,
    List<String>? opened,
    Future<List<LrPublic>> Function()? lrs,
    VoidCallback? onOffers,
  }) =>
      CustomerHomeV3(
        key: key,
        onBook: () {},
        onBookFrom: (d) => drafts?.add(d),
        onOpenBooking: (id) => opened?.add('b:$id'),
        onOpenLoad: (id) => opened?.add('l:$id'),
        onOpenTrips: () {},
        onOpenOffers: onOffers,
        onOpenTemplates: () {},
        more: const [Text('more tile', key: ValueKey('moreTile'))],
        bookings: bookingStream ?? () => Stream.value(bookings),
        loads: () => Stream.value(loads),
        lrs: lrs ?? () async => const [],
        catalog: () async => specs,
        loadLayout: () async => layout ?? CustomerHomeSections.defaults,
        saveLayout: (l) async => saved?.add(l),
      );

  Future<void> tall(WidgetTester t, {double width = 400}) async {
    t.view.physicalSize = Size(width, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    specs = (await t.runAsync(() => VehicleCatalog.load()))!;
  }

  testWidgets('skeleton until the layout and both lists arrive', (t) async {
    await tall(t);
    final ctrl = StreamController<List<Booking>>();
    await t.pumpWidget(host(home(bookingStream: () => ctrl.stream)));
    await t.pump();
    expect(find.byKey(const ValueKey('h3Skeleton')), findsOneWidget);
    ctrl.add(const []);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('h3Skeleton')), findsNothing);
    expect(find.byKey(const ValueKey('h3Hero')), findsOneWidget);
    await ctrl.close();
  });

  testWidgets('first run: the hero explains a first booking; no trip, routes or LRs', (t) async {
    await tall(t);
    await t.pumpWidget(host(home()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('h3FirstRun')), findsOneWidget);
    expect(find.byKey(const ValueKey('h3Trip')), findsNothing);
    expect(find.byKey(const ValueKey('h3Promise')), findsOneWidget);
    expect(find.text(en('h3Promise').replaceAll('{app}', 'Load 20')), findsOneWidget);
    expect(find.byKey(const ValueKey('moreTile')), findsOneWidget);
  });

  testWidgets('a running trip, then waiting loads; recent routes book again with the route filled', (t) async {
    await tall(t);
    final opened = <String>[];
    final drafts = <WizardDraft>[];
    await t.pumpWidget(host(home(
      bookings: [booking('B1', 'delivered'), booking('B2', 'in_transit')],
      loads: [load('L1', 'open', pickup: 'Pune', drop: 'Surat')],
      opened: opened,
      drafts: drafts,
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('h3HeroSub')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('h3OpenTrip')));
    expect(opened, ['b:B2']);
    await t.tap(find.byKey(const ValueKey('h3Route_Pune_Surat')));
    expect(drafts.single.pickup, 'Pune');

    await t.pumpWidget(host(home(key: const ValueKey(2), loads: [load('L1', 'open')], opened: opened)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('h3Waiting')), findsOneWidget);
  });

  testWidgets('vehicle carousel only with vehicleCatalog on; a vehicle starts a booking with its type', (t) async {
    await tall(t);
    final drafts = <WizardDraft>[];
    await t.pumpWidget(host(home(loads: [load('L1', 'delivered')], drafts: drafts)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('h3Vehicles')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.vehicleCatalog: true});
    await t.pumpWidget(host(home(key: const ValueKey(2), loads: [load('L1', 'delivered')], drafts: drafts)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('h3Vehicles')), findsOneWidget);
    final first = specs.firstWhere((s) => s.legacyId != null);
    await t.tap(find.byKey(ValueKey('h3Vehicle_${first.id}')));
    expect(drafts.single.vehicleType, first.legacyId);
  });

  testWidgets('offers and referral follow the offers switch; recent LRs show when the person turns them on', (t) async {
    await tall(t);
    var lrReads = 0;
    final layout = CustomerHomeSections.defaults.toggle(CustomerHomeSections.lrs);
    await t.pumpWidget(host(home(
      loads: [load('L1', 'delivered')],
      onOffers: () {},
      layout: layout,
      lrs: () async {
        lrReads++;
        return [LrPublic.fromDoc('x1', {'lrNo': 'LR-0007', 'route': 'Delhi - Jaipur', 'bookingId': 'B9'})];
      },
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('h3Offers')), findsNothing);
    expect(find.text('LR-0007'), findsOneWidget);
    expect(lrReads, 1);
    OffersSwitchService.notifier.value = const OffersSwitch(credits: true, referral: true);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('h3Offers')), findsOneWidget);
    expect(find.byKey(const ValueKey('h3Referral')), findsOneWidget);
    expect(lrReads, 1);
  });

  testWidgets('the saved order and hidden sections are used; Arrange saves the new layout', (t) async {
    await tall(t);
    final saved = <HomeLayout>[];
    final start = CustomerHomeSections.defaults.move(CustomerHomeSections.all.indexOf('promise'), 0).toggle('more');
    await t.pumpWidget(host(home(loads: [load('L1', 'delivered')], layout: start, saved: saved)));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byKey(const ValueKey('h3Promise'))).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey('h3Hero'))).dy));
    expect(find.byKey(const ValueKey('moreTile')), findsNothing);
    await t.tap(find.byKey(const ValueKey('h3Arrange')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('hlSwitch_promise')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('hlDone')));
    await t.pumpAndSettle();
    expect(saved.single.isHidden('promise'), isTrue);
    expect(find.byKey(const ValueKey('h3Promise')), findsNothing);
  });

  testWidgets('a broken list shows an error with retry above the sections', (t) async {
    await tall(t);
    await t.pumpWidget(host(home(bookingStream: () => Stream.error(StateError('x')))));
    await t.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, en('retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('h3Hero')), findsOneWidget);
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
      await tall(t, width: 320);
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.vehicleCatalog: true});
      OffersSwitchService.notifier.value = const OffersSwitch(credits: true, referral: true);
      await t.pumpWidget(host(
          home(bookings: [booking('B2', 'in_transit')], loads: [load('L1', 'open')], onOffers: () {}, layout: CustomerHomeSections.defaults.toggle('lrs'),
              lrs: () async => [LrPublic.fromDoc('x1', {'lrNo': 'LR-0007', 'route': 'Delhi - Jaipur'})]),
          lang: lang, b: b, scale: 2));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('h3Hero')), findsOneWidget);
    });
  }
}
