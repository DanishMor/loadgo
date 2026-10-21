import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/widgets/common.dart';

import 'test_utils.dart';

/// Z8: a new account sees an empty state that says what to do next on every main tab.
void main() {
  // (file, title key) of the first-run empty states of the main tabs.
  const screens = {
    'lib/driver/my_offers_screen.dart': 'noMyOffers',
    'lib/driver/v2/my_bids_v2.dart': 'noMyOffers',
    'lib/driver/upcoming_trips.dart': 'noUpcomingTrips',
    'lib/driver/earnings_view.dart': 'noEarningsYet',
    'lib/driver/v2/earnings_v2.dart': 'noEarningsYet',
    'lib/driver/available_loads_view.dart': 'noAvailableLoads',
    'lib/fleet/transporter_loads_screen.dart': 'trpNoLoads',
    'lib/fleet/transporter_trips_screen.dart': 'trpNoTrips',
    'lib/fleet/fleet_vehicles_screen.dart': 'fleetNoVehicles',
    'lib/fleet/fleet_analytics_screen.dart': 'fleetNoVehicles',
  };

  test('each first-run empty state of the main tabs also has a line saying what to do next', () {
    screens.forEach((file, key) {
      final line = File(file).readAsLinesSync().firstWhere((l) => l.contains("'$key'") && l.contains('EmptyState('), orElse: () => '');
      expect(line, isNotEmpty, reason: '$file: no EmptyState for $key');
      expect(line.contains('subtitle:') || line.contains('action:'), isTrue, reason: '$file: $key has no next step');
    });
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.urdu]) {
    testWidgets('the next-step lines fit at 360x640, 2.0x text, dark (${lang.name})', (tester) async {
      languageNotifier.value = lang;
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      addTearDown(() => languageNotifier.value = AppLanguage.english);
      for (final k in ['frOffersSub', 'frEarningsSub', 'frUpcomingSub', 'frAvailSub']) {
        await tester.pumpWidget(LanguageScope(
          notifier: languageNotifier,
          child: MaterialApp(
            theme: ThemeData.dark(),
            builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2)), child: w!),
            home: Builder(builder: (c) => Scaffold(body: EmptyState(icon: Icons.inbox_rounded, title: tr(c, 'noMyOffers'), subtitle: tr(c, k)))),
          ),
        ));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: k);
        expect(find.text(tr(tester.element(find.byType(EmptyState)), k)), findsOneWidget);
      }
    });
  }
}
