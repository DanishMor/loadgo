import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/assistant/assistant_engine.dart';
import 'package:transport_app/core/assistant/sahayak_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/driver/simple_home_screen.dart';

import 'test_utils.dart';

Widget host(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: child));

void main() {
  setUp(() {
    languageNotifier.value = AppLanguage.english;
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'u1');
  });

  testWidgets('fleet owner Sahayak: FAQ chips only, no post-load chip, no action buttons', (t) async {
    await t.pumpWidget(host(const SahayakButton(role: 'fleet', actions: SahayakActions())));
    await t.tap(find.byKey(const ValueKey('sahayakButton')));
    await t.pumpAndSettle();
    expect(find.text('Price offer'), findsOneWidget);
    expect(find.text('Post a load'), findsNothing);
    await t.enterText(find.byType(TextField), 'post load from Delhi to Jaipur');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await settle(t);
    expect(find.text('Open Post Load'), findsNothing, reason: 'fleet owners do not post loads');
  });

  test('the engine never gives a fleet owner post-load or nearby-loads actions', () {
    for (final text in ['post load from Delhi to Jaipur', 'nearby loads', 'loads near me']) {
      final r = const RuleEngine().reply(text, role: 'fleet');
      expect(r.action, isNot(AssistantAction.openPostLoad), reason: text);
      expect(r.action, isNot(AssistantAction.openNearbyLoads), reason: text);
    }
  });

  testWidgets('Simple Mode home has the Sahayak button, and its actions open the simple lists', (t) async {
    await t.pumpWidget(host(const SimpleDriverHome()));
    expect(find.byKey(const ValueKey('sahayakButton')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sahayakButton')));
    await t.pumpAndSettle();
    await t.tap(find.text('My booking'));
    await settle(t);
    expect(find.text('Open my bookings'), findsOneWidget);
  });

  test('every home in both apps carries a Sahayak entry', () {
    for (final f in ['lib/driver/driver_home_screen.dart', 'lib/customer/customer_home_screen.dart', 'lib/fleet/fleet_home_screen.dart', 'lib/driver/simple_home_screen.dart']) {
      expect(File(f).readAsStringSync(), contains('SahayakButton('), reason: f);
    }
  });
}
