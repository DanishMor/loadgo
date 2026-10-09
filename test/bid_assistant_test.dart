import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pricing/bid_assistant.dart';
import 'package:transport_app/core/pricing/offer_bounds.dart';
import 'package:transport_app/core/widgets/bid_assistant_panel.dart';
import 'package:transport_app/core/widgets/logistics_labels.dart';

import 'test_utils.dart';

/// MASTER-6 Task 24: the bid assistant.
void main() {
  List<String> keys(BidSuggestion s) => [for (final r in s.reasons) r.key];

  test('no estimate, no suggestion', () {
    expect(BidAssistant.suggest(estimateTotal: null), isNull);
    expect(BidAssistant.suggest(estimateTotal: 0), isNull);
    expect(BidAssistant.suggest(estimateTotal: -5), isNull);
  });

  test('around the estimate: lower, fair, higher in whole ten rupees, in order', () {
    final s = BidAssistant.suggest(estimateTotal: 400000)!;
    expect((s.low, s.fair, s.high), (360000, 400000, 460000));
    expect(s.low <= s.fair && s.fair <= s.high, isTrue);
    expect([s.low, s.fair, s.high].every((v) => v % BidAssistant.step == 0), isTrue);
    expect(keys(s), ['bidWhyEstimate', 'bidWhyRule']);
  });

  test('the low end is raised to cover toll and fuel with a margin, and the reason says so', () {
    final s = BidAssistant.suggest(estimateTotal: 400000, runningCost: 350000)!;
    // 350000 * 120% = 420000 would be above the fair price, so the low end stops at the fair price
    expect(s.low, lessThanOrEqualTo(s.fair));
    expect(s.low, s.fair);
    expect(keys(s), contains('bidWhyCostRaised'));
    final roomy = BidAssistant.suggest(estimateTotal: 400000, runningCost: 100000)!;
    expect(roomy.low, 360000);
    expect(keys(roomy), contains('bidWhyCost'));
    expect(keys(roomy), isNot(contains('bidWhyCostRaised')));
  });

  test('the customer budget adds a reason either way', () {
    expect(keys(BidAssistant.suggest(estimateTotal: 400000, budgetPaise: 450000)!), contains('bidWhyBudgetOk'));
    expect(keys(BidAssistant.suggest(estimateTotal: 400000, budgetPaise: 300000)!), contains('bidWhyBudgetLow'));
    expect(keys(BidAssistant.suggest(estimateTotal: 400000, budgetPaise: 0)!), isNot(contains('bidWhyBudgetOk')));
  });

  test('every suggestion is accepted by the same bounds the rules use, over many estimates and costs', () {
    for (final e in [1, 99, 100, 1234, 5000, 99999, 400000, 12345678]) {
      for (final cost in [0, 1, 500, 100000, 99999999]) {
        final s = BidAssistant.suggest(estimateTotal: e, runningCost: cost)!;
        for (final v in [s.low, s.fair, s.high]) {
          expect(OfferBounds.check(v, e), isNull, reason: 'estimate $e cost $cost price $v');
        }
        expect(s.low <= s.fair && s.fair <= s.high, isTrue, reason: 'estimate $e cost $cost');
      }
    }
  });

  testWidgets('the dialog shows the chips and the reasons; a chip fills the price field', (tester) async {
    final s = BidAssistant.suggest(estimateTotal: 400000, runningCost: 100000, budgetPaise: 300000)!;
    int? result;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => result = await askPricePaise(c, title: 'Offer', label: 'Your price', assist: (ctx, set) => BidAssistantPanel(suggestion: s, onPick: set)),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.text('Suggested price'), findsOneWidget);
    expect(find.textContaining('The fare estimate for this trip is ₹'), findsOneWidget);
    expect(find.textContaining('below the estimate'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bidPick_high')));
    await tester.pump();
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('priceField'))).controller!.text, '4600');
    await tester.tap(find.byKey(const ValueKey('priceSubmit')));
    await settle(tester);
    expect(result, 460000);
  });
}
