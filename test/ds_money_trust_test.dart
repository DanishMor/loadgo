import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/contrast.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/money_text.dart';
import 'package:transport_app/core/widgets/ds/status_badge.dart';
import 'package:transport_app/core/widgets/fare_breakdown.dart';
import 'package:transport_app/core/widgets/verification_badges.dart';

/// L11: money display, fare breakdown and trust / verification badges.
Widget host(Widget child, {Brightness b = Brightness.light, double scale = 1.0, AppLanguage lang = AppLanguage.english}) {
  final language = ValueNotifier(lang);
  final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(b),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: dir, child: w!)),
      home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
    ),
  );
}

void main() {
  group('MoneyText.format', () {
    test('Indian grouping, paise only when there are some, negatives and zero', () {
      expect(MoneyText.format(0), '₹ 0');
      expect(MoneyText.format(100), '₹ 1');
      expect(MoneyText.format(123456700), '₹ 12,34,567');
      expect(MoneyText.format(150), '₹ 1.50');
      expect(MoneyText.format(5), '₹ 0.05');
      expect(MoneyText.format(-250000), '-₹ 2,500');
      expect(MoneyText.format(99999999), '₹ 9,99,999.99');
    });

    test('a huge amount does not break, and hidden never leaks the number', () {
      expect(MoneyText.format(9007199254740991), contains('₹ '));
      final hidden = MoneyText.format(123456, hidden: true);
      expect(hidden, '₹ ••••');
      expect(hidden.contains('1'), isFalse);
      expect(MoneyText.format(500, signed: true), '+₹ 5');
      expect(MoneyText.format(-500, signed: true), '-₹ 5');
      expect(MoneyText.format(0, signed: true), '₹ 0');
    });
  });

  group('MoneyText widget', () {
    testWidgets('shows the amount in tabular digits at each size', (t) async {
      for (final s in MoneySize.values) {
        await t.pumpWidget(host(MoneyText(1450000, size: s)));
        final text = t.widget<Text>(find.text('₹ 14,500'));
        expect(text.style!.fontSize, s.fontSize);
        expect(text.style!.fontFeatures, isNotEmpty);
      }
    });

    testWidgets('hidden shows dots and is spoken as hidden, in the language', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(const MoneyText(500000, hidden: true)));
      expect(find.text('₹ ••••'), findsOneWidget);
      expect(find.text('₹ 5,000'), findsNothing);
      expect(find.bySemanticsLabel('Amount hidden'), findsOneWidget);
      await t.pumpWidget(host(const MoneyText(500000, hidden: true), lang: AppLanguage.hindi));
      expect(find.bySemanticsLabel('राशि छिपी है'), findsOneWidget);
      await t.pumpWidget(host(const MoneyText(500000)));
      expect(find.bySemanticsLabel('₹ 5,000'), findsOneWidget);
      h.dispose();
    });

    for (final b in Brightness.values) {
      testWidgets('credits are green and debits red, both readable, in ${b.name}', (t) async {
        final surface = DsColors.of(b).surface;
        await t.pumpWidget(host(const Column(children: [MoneyText(100000, signed: true), MoneyText(-100000, signed: true), MoneyText(0, signed: true)]), b: b));
        final credit = t.widget<Text>(find.text('+₹ 1,000')).style!.color!;
        final debit = t.widget<Text>(find.text('-₹ 1,000')).style!.color!;
        expect(contrastRatio(credit, surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(debit, surface), greaterThanOrEqualTo(4.5));
        expect((credit.g * 255).round(), greaterThan((credit.r * 255).round()));
        expect((debit.r * 255).round(), greaterThan((debit.g * 255).round()));
      });
    }

    testWidgets('an explicit colour wins, strike draws a line', (t) async {
      await t.pumpWidget(host(const MoneyText(9900, color: Color(0xFF123456), strike: true)));
      final s = t.widget<Text>(find.text('₹ 99')).style!;
      expect(s.color, const Color(0xFF123456));
      expect(s.decoration, TextDecoration.lineThrough);
    });

    for (final lang in [AppLanguage.urdu, AppLanguage.hindi]) {
      testWidgets('digits stay left to right in ${lang.name} and fit at 2.0x', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(const SizedBox(width: 200, child: MoneyText(123456700, size: MoneySize.display)), scale: 2.0, lang: lang));
        expect(t.takeException(), isNull);
        final text = t.widget<Text>(find.text('₹ 12,34,567'));
        expect(text.textDirection, isNull);
        final box = t.widget<Directionality>(find.ancestor(of: find.text('₹ 12,34,567'), matching: find.byType(Directionality)).first);
        expect(box.textDirection, TextDirection.ltr);
      });
    }

    testWidgets('the visibility button flips and says what it will do', (t) async {
      var hidden = true;
      await t.pumpWidget(StatefulBuilder(builder: (c, set) => host(MoneyVisibilityButton(hidden: hidden, onChanged: (v) => set(() => hidden = v)))));
      expect(find.byTooltip('Show amount'), findsOneWidget);
      await t.tap(find.byType(IconButton));
      await t.pump();
      expect(hidden, isFalse);
      expect(find.byTooltip('Hide amount'), findsOneWidget);
      expect(t.getSize(find.byType(IconButton)).width, greaterThanOrEqualTo(48));
    });
  });

  group('FareBreakdownView', () {
    const rule = PricingRule(baseFare: 10000, perKm: 2000, minimumFare: 50000, loadingCharge: 3000, waitingPerHour: 5000, helperCharge: 30000);
    final fare = FareCalculator.calculate(rule: rule, distanceKm: 100, platformFeePercent: 5, gstPercent: 5, helpers: 1);

    testWidgets('every line is a MoneyText and the total adds up', (t) async {
      await t.pumpWidget(host(FareBreakdownView(fare: fare)));
      expect(find.byType(MoneyText), findsWidgets);
      expect(find.text(MoneyText.format(fare.total)), findsOneWidget);
      expect(find.text(MoneyText.format(fare.tripFare)), findsOneWidget);
      expect(fare.total, fare.tripFare + fare.platformFee + fare.gst);
    });

    testWidgets('the explain tap opens one plain sentence', (t) async {
      await t.pumpWidget(host(FareBreakdownView(fare: fare, explain: true)));
      await t.tap(find.byKey(const ValueKey('fexInfo_fexBase')));
      await t.pump();
      expect(find.byKey(const ValueKey('fexText_fexBase')), findsOneWidget);
    });

    for (final lang in [AppLanguage.tamil, AppLanguage.urdu]) {
      for (final b in Brightness.values) {
        testWidgets('fits 360x640 at 2.0x: ${lang.name} ${b.name}', (t) async {
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(host(FareBreakdownView(fare: fare, explain: true), b: b, scale: 2.0, lang: lang));
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('verification badges', () {
    testWidgets('each state has its own tone and icon; a missing document is quiet', (t) async {
      final user = {
        'phone': '+919876543210',
        'verified': true,
        'driverKyc': {'dlNumber': 'DL0420110012345', 'pan': '', 'rcNumber': null},
      };
      await t.pumpWidget(host(VerificationBadges(user: user, isDriver: true)));
      expect(find.byType(StatusBadge), findsNWidgets(5));
      expect(find.byIcon(Icons.phone_android_rounded), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline_rounded), findsNWidgets(3));
      await t.pumpWidget(host(VerificationBadges(user: const {'phone': '+919876543210', 'driverKyc': {'dlNumber': 'DL0420110012345'}}, isDriver: true)));
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget, reason: 'given but not reviewed');
    });

    testWidgets('the value is masked unless revealed', (t) async {
      final user = {'phone': '+919876543210', 'verified': true, 'driverKyc': {'dlNumber': 'DL0420110012345'}};
      await t.pumpWidget(host(VerificationBadges(user: user, isDriver: true)));
      expect(find.text('DL0420110012345'), findsNothing);
      await t.pumpWidget(host(VerificationBadges(user: user, isDriver: true, reveal: true)));
      expect(find.text('DL0420110012345'), findsOneWidget);
    });

    test('a status badge can carry its own icon', () {
      const b = StatusBadge(label: 'x', tone: StatusTone.success, icon: Icons.shield_outlined);
      expect(b.icon, Icons.shield_outlined);
    });
  });
}
