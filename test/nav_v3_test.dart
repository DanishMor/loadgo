import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/navigation/app_routes.dart';
import 'package:transport_app/core/search/global_search.dart';
import 'package:transport_app/core/search/global_search_screen.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/customer/v3/customer_home_v3.dart';

final lr = LrPublic.fromDoc('x1', {'lrNo': 'LR-2027-0042', 'bookingId': 'B42', 'pickup': 'Pune', 'drop': 'Surat', 'route': 'Pune - Surat', 'goods': 'Cotton bales', 'consigneeName': 'Shah Textiles', 'vehicleNumber': 'MH12AB1234'});

/// E25: bilty in global search and the search entry on the v3 customer home (flag navV3).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'c1', phoneNumber: '+919800000001'));
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'c1', auth: () => auth);
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(() {
    FeaturesService.reset();
    AppRoutes.openBooking = null;
  });

  test('a bilty entry opens its booking and matches number, goods, party and vehicle', () {
    final e = GlobalSearch.fromLr(lr);
    expect(e.kind, SearchKind.lr);
    expect(e.id, 'B42');
    final index = GlobalSearch([e]);
    for (final q in ['0042', 'cotton', 'shah', 'mh12ab']) {
      expect(index.search(q).expand((s) => s.hits), isNotEmpty, reason: q);
    }
  });

  Widget search() => LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(
          home: GlobalSearchScreen(
            isDriver: false,
            debounce: Duration.zero,
            loads: Stream.value(const []),
            bookings: Stream.value(const []),
            tickets: Stream.value(const []),
            places: Stream.value(const []),
            lrs: Stream.value([lr]),
          ),
        ),
      );

  testWidgets('bilty results only with navV3 on; a tap opens the booking', (t) async {
    await t.pumpWidget(search());
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('globalSearchField')), 'shah');
    await t.pumpAndSettle();
    expect(find.text('LR-2027-0042'), findsNothing);

    FeaturesService.notifier.value = const Features(flags: {FeatureKey.navV3: true});
    String? opened;
    AppRoutes.openBooking = (context, id, {required bool isDriver}) => opened = id;
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(search());
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('globalSearchField')), 'shah');
    await t.pumpAndSettle();
    expect(find.text('LR-2027-0042'), findsOneWidget);
    await t.tap(find.text('LR-2027-0042'));
    await t.pumpAndSettle();
    expect(opened, 'B42');
  });

  testWidgets('the v3 customer home shows a search button only with navV3 on', (t) async {
    t.view.physicalSize = const Size(400, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Widget home() => LanguageScope(
          notifier: languageNotifier,
          child: MaterialApp(
            home: Scaffold(
              body: CustomerHomeV3(
                onBook: () {},
                onBookFrom: (_) {},
                onOpenBooking: (_) {},
                onOpenLoad: (_) {},
                onOpenTrips: () {},
                bookings: () => Stream.value(const []),
                loads: () => Stream.value(const []),
                loadLayout: () async => CustomerHomeSections.defaults,
              ),
            ),
          ),
        );
    await t.pumpWidget(home());
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('h3Search')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.navV3: true});
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(home());
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('h3Search')), findsOneWidget);
  });
}
