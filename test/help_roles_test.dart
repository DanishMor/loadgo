import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/settings/help_screen.dart';

/// MASTER-5 Task 42: each role sees the questions that are for it.
void main() {
  test('every question belongs to at least one role and has an answer in all 12 languages', () {
    expect(HelpFaq.roles.keys.toList(), [for (var i = 1; i <= HelpScreen.faqCount; i++) i]);
    for (final e in HelpFaq.roles.entries) {
      expect(e.value, isNotEmpty);
      for (final l in AppLanguage.values) {
        expect(T.get('faqQ${e.key}', l).trim(), isNotEmpty, reason: 'faqQ${e.key} ${l.name}');
        expect(T.get('faqA${e.key}', l).trim(), isNotEmpty, reason: 'faqA${e.key} ${l.name}');
      }
    }
  });

  test('role lists: drivers do not get the customer or transporter questions and the reverse', () {
    final driver = HelpFaq.forRole('driver'), customer = HelpFaq.forRole('customer'), fleet = HelpFaq.forRole('fleet');
    expect(driver, containsAll([6, 14, 15]));
    expect(driver, isNot(contains(1)));
    expect(driver, isNot(contains(16)));
    expect(customer, containsAll([1, 12, 13, 18]));
    expect(customer, isNot(contains(6)));
    expect(fleet, containsAll([1, 12, 16, 17]));
    expect(fleet, isNot(contains(18)));
    for (final common in [2, 3, 4, 5, 7, 8, 9, 10, 11]) {
      expect([driver, customer, fleet].every((l) => l.contains(common)), isTrue, reason: 'question $common is for everyone');
    }
    expect(HelpFaq.forRole(null), HelpFaq.roles.keys.toList());
  });

  Widget app(Widget home) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: home));

  testWidgets('the screen shows only the role\'s questions, plus one asked for by search', (tester) async {
    Future<void> reveal(Finder f) async {
      for (var n = 0; n < 30 && f.evaluate().isEmpty; n++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -200));
        await tester.pump();
      }
    }

    await tester.pumpWidget(app(const HelpScreen(role: 'driver')));
    await reveal(find.byKey(const ValueKey('faq14')));
    expect(find.byKey(const ValueKey('faq14')), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pump();
    expect(find.byKey(const ValueKey('faq16')), findsNothing);
    await tester.pumpWidget(app(const HelpScreen(role: 'driver', openFaq: 16, key: ValueKey('again'))));
    await reveal(find.byKey(const ValueKey('faq16')));
    expect(find.byKey(const ValueKey('faq16')), findsOneWidget);
    expect(tester.widget<ExpansionTile>(find.byKey(const ValueKey('faq16'))).initiallyExpanded, isTrue);
  });
}
