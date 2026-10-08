import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/widgets/role_tour_card.dart';

import 'test_utils.dart';

/// MASTER-5 Task 27: a short "how it works" card, once per role on a device.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(String role) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: RoleTourCard(key: ValueKey('w_$role'), role: role))));

  test('every role has a title and three steps with text in all 12 languages', () {
    for (final role in RoleTour.roles) {
      final (title, steps) = RoleTour.keys(role);
      expect(steps, hasLength(3));
      for (final k in [title, ...steps, 'tourGotIt']) {
        for (final l in AppLanguage.values) {
          expect(T.get(k, l).trim(), isNotEmpty, reason: '$k ${l.name}');
        }
      }
    }
  });

  for (final role in RoleTour.roles) {
    testWidgets('$role: shown the first time, gone for good after Got it', (tester) async {
      await tester.pumpWidget(app(role));
      await settle(tester);
      expect(find.byKey(ValueKey('tour_$role')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tourGotIt')));
      await settle(tester);
      expect(find.byKey(ValueKey('tour_$role')), findsNothing);
      // a new screen of the same role: still hidden
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(role));
      await settle(tester);
      expect(find.byKey(ValueKey('tour_$role')), findsNothing);
      // another role is not affected
      final other = RoleTour.roles.firstWhere((r) => r != role);
      await tester.pumpWidget(app(other));
      await settle(tester);
      expect(find.byKey(ValueKey('tour_$other')), findsOneWidget);
    });
  }
}
