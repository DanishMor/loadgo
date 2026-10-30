import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/paged.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/customer/customer_home_screen.dart';
import 'package:transport_app/customer/v2/customer_home_v2.dart';
import 'package:transport_app/customer/v2/customer_shell_v2.dart';
import 'package:transport_app/customer/v2/trips_tab_v2.dart';

/// U18/U23: the new customer app (Home, Trips, Help, Profile) and the old home behind the switch.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'customer1', phoneNumber: '+919800000001'));
    Backend.useFakes(db: db, uid: () => 'customer1', auth: () => auth);
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Widget host({Brightness b = Brightness.light, double scale = 1.0}) => LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(
          theme: AppTheme.build(b),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
          home: const CustomerHomeScreen(),
        ),
      );

  test('RecentRoute keeps the newest distinct routes and skips blanks', () async {
    Future<Load> l(String p, String d) async {
      final ref = await db.collection('loads').add({'pickup': p, 'drop': d});
      return Load.fromDoc(await ref.get());
    }

    final r = RecentRoute.from([await l('Delhi', 'Jaipur'), await l('delhi ', 'JAIPUR'), await l('', 'Pune'), await l('Pune', 'Surat')]);
    expect([for (final x in r) '${x.pickup}>${x.drop}'], ['Delhi>Jaipur', 'Pune>Surat']);
    expect(RecentRoute.from([await l('A1', 'B1'), await l('A2', 'B2'), await l('A3', 'B3')], max: 2).length, 2);
  });

  testWidgets('uiV2 ON (default): the new shell with four tabs and a big Book action', (t) async {
    t.view.physicalSize = const Size(360 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(host());
    await settle(t);
    expect(find.byType(CustomerShellV2), findsOneWidget);
    expect(find.byKey(const ValueKey('homeBook')), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const ValueKey('homeTrust')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('homeTrust')), findsOneWidget);
    for (final label in ['Home', 'Trips', 'Help', 'Profile']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)), findsOneWidget, reason: label);
    }
    // Bid mode is named on the home only when dispatchV2 is on.
    expect(find.text('Bid'), findsNothing);
  });

  testWidgets('E21: homeV3 ON shows the arrangeable home; it needs designV3', (t) async {
    t.view.physicalSize = const Size(360 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.homeV3: true});
    await t.pumpWidget(host());
    await settle(t);
    expect(find.byKey(const ValueKey('h3Hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('homeHero')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.homeV3: true, FeatureKey.designV3: false});
    await settle(t);
    expect(find.byKey(const ValueKey('homeHero')), findsOneWidget);
    expect(find.byKey(const ValueKey('h3Hero')), findsNothing);
  });

  testWidgets('uiV2 OFF: the older home is still there', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.uiV2: false});
    await t.pumpWidget(host());
    await settle(t);
    expect(find.byType(CustomerShellV2), findsNothing);
    expect(find.byKey(const ValueKey('homeBook')), findsNothing);
  });

  testWidgets('a waiting load shows on Home and under Trips > Active; Past is empty', (t) async {
    t.view.physicalSize = const Size(360 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 25000, pickupDate: DateTime(2030, 10, 5), notes: '');
    await t.pumpWidget(host(b: Brightness.dark, scale: 2.0));
    await settle(t);
    await t.scrollUntilVisible(find.byKey(const ValueKey('homeWaiting')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('homeWaiting')), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const ValueKey('recent_Delhi_Jaipur')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('recent_Delhi_Jaipur')), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Trips')));
    await settle(t);
    expect(find.textContaining('Delhi → Jaipur'), findsWidgets);
    expect(find.text('Waiting for drivers'), findsWidgets);
    await t.ensureVisible(find.text('Past', skipOffstage: false));
    await t.pump();
    await t.tap(find.text('Past'));
    await settle(t);
    expect(find.text('Finished trips will show here.'), findsOneWidget);
  });

  Widget tripsHost({required Stream<Paged<Booking>> Function(int) bookings, required Stream<List<Load>> Function() loads, VoidCallback? onBook}) => LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: TripsTabV2(bookings: bookings, loads: loads, onOpenBooking: (_) {}, onOpenLoad: (_) {}, onBookAgain: (_) {}, onBook: onBook),
          ),
        ),
      );

  testWidgets('Trips tab, empty: says so and offers Book a truck (Active only)', (t) async {
    var booked = 0;
    await t.pumpWidget(tripsHost(bookings: (_) => Stream.value(const Paged<Booking>.all([])), loads: () => Stream.value(const <Load>[]), onBook: () => booked++));
    await settle(t);
    expect(find.text('No trip right now. Book a truck to start.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('tripsBook')));
    expect(booked, 1);
  });

  testWidgets('Trips tab, error: a friendly message with Retry, not a raw exception', (t) async {
    await t.pumpWidget(tripsHost(bookings: (_) => Stream.value(const Paged<Booking>.all([])), loads: () => Stream<List<Load>>.error(StateError('boom'))));
    await settle(t);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.text('Retry'), findsWidgets);
  });
}
