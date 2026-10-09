import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pricing/cancel_preview.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/widgets/fare_breakdown.dart';

import 'test_utils.dart';

/// MASTER-6 Task 17: fare transparency and the cancel charge preview.
void main() {
  FareBreakdown fare() => const FareBreakdown(
        distanceKm: 120,
        baseFare: 50000,
        distanceCharge: 336000,
        loadingCharge: 20000,
        unloadingCharge: 20000,
        waitingCharge: 0,
        extraStopCharge: 15000,
        minimumFareAdjustment: 0,
        surgeCharge: 20000,
        surgePercent: 5,
        surgeKind: 'peak',
        platformFee: 22000,
        gst: 14000,
        platformFeePercent: 5,
        gstPercent: 18,
      );

  test('the preview uses the policy: free minutes, the percent clamped to the min and max, the scheduled grace', () {
    const policy = CancellationPolicy(freeMinutes: 15, chargePercent: 10, minCharge: 5000, maxCharge: 100000, scheduledFreeHours: 2);
    final p = CancelPreview.of(policy, farePaise: 400000);
    expect((p.freeMinutes, p.chargePaise, p.scheduledFreeHours), (15, 40000, 2));
    expect(CancelPreview.of(policy, farePaise: 10000).chargePaise, 5000); // the minimum
    expect(CancelPreview.of(policy, farePaise: 5000000).chargePaise, 100000); // the maximum
    expect(CancelPreview.of(policy, farePaise: null).chargePaise, 5000); // no estimate: the minimum
    expect(CancelPreview.openLoadCharge, 0);
  });

  test('the preview shows exactly what a real cancellation after the free minutes records', () {
    const policy = CancellationPolicy();
    for (final fare in [null, 20000, 400000, 3000000]) {
      expect(CancelPreview.of(policy, farePaise: fare).chargePaise, policy.chargeFor(elapsed: Duration(minutes: policy.freeMinutes), farePaise: fare));
      expect(policy.chargeFor(elapsed: Duration(minutes: policy.freeMinutes - 1), farePaise: fare), 0);
    }
  });

  testWidgets('a line explains itself on tap and hides again', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: FareBreakdownView(fare: fare(), explain: true))))));
    await settle(tester);
    expect(find.byKey(const ValueKey('fexText_fexSurge')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('fexInfo_fexSurge')));
    await tester.pump();
    expect(find.text('Extra percent in busy hours, at night or on festival days.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fexInfo_fexSurge')));
    await tester.pump();
    expect(find.byKey(const ValueKey('fexText_fexSurge')), findsNothing);
    // the plain view (no explain) has no info buttons
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: FareBreakdownView(fare: fare()))))));
    await tester.pump();
    expect(find.byKey(const ValueKey('fexInfo_fexSurge')), findsNothing);
  });

  testWidgets('the sheet shows the breakdown, the disclaimer and the four cancel lines in rupees', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Builder(builder: (c) => TextButton(onPressed: () => showFareBreakdown(c, fare()), child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.byKey(const ValueKey('fexCancelOpen')), findsOneWidget);
    expect(find.textContaining('first 15 minutes'), findsOneWidget);
    expect(find.textContaining('After that: ₹'), findsOneWidget);
    expect(find.textContaining('free until 2 hours before pickup'), findsOneWidget);
  });

  testWidgets('every explained line key has a translation in every language', (tester) async {
    for (final lang in AppLanguage.values) {
      languageNotifier.value = lang;
      await tester.pumpWidget(const SizedBox()); // a fresh view: nothing open yet
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: FareBreakdownView(fare: fare(), explain: true))))));
      await tester.pump();
      for (final k in ['fexBase', 'fexDistance', 'fexHandling', 'fexStops', 'fexSurge', 'fexPlatform', 'fexGst']) {
        await tester.tap(find.byKey(ValueKey('fexInfo_$k')).first);
        await tester.pump();
        final text = tester.widget<Text>(find.byKey(ValueKey('fexText_$k')).first).data!;
        expect(text.isNotEmpty && text != k, isTrue, reason: '$lang $k');
      }
    }
    languageNotifier.value = AppLanguage.english;
  });
}
