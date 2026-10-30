import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/core/widgets/ds/app_bottom_nav.dart';
import 'package:transport_app/core/widgets/ds/app_button.dart';
import 'package:transport_app/core/widgets/ds/app_text_field.dart';
import 'package:transport_app/core/widgets/ds/bid_card.dart';
import 'package:transport_app/core/widgets/ds/driver_mini_card.dart';
import 'package:transport_app/core/widgets/ds/money_text.dart';
import 'package:transport_app/core/widgets/ds/person_kit.dart';
import 'package:transport_app/core/widgets/ds/route_ribbon.dart';
import 'package:transport_app/core/widgets/ds/sheet_kit.dart';
import 'package:transport_app/core/widgets/ds/status_badge.dart';
import 'package:transport_app/core/widgets/ds/status_timeline_v2.dart';

/// E10: every core component in every look, at three phone widths, at 2.0x
/// text, in long and right-to-left languages, without an overflow or a throw.
Widget gallery(AppLanguage lang) {
  String t(String k) => T.data[k]?[lang] ?? k;
  final long = t('themeLookSignature');
  return ListView(key: const ValueKey('gallery'), padding: const EdgeInsets.all(DsSpace.gutter), children: [
    for (final k in AppButtonKind.values) ...[AppButton(label: long, onPressed: () {}, kind: k, icon: Icons.check), const SizedBox(height: DsSpace.s2)],
    AppButton(label: long, onPressed: () {}, big: true),
    AppCard(child: Text(long)),
    StatusBadge(label: long, tone: StatusTone.success),
    AppTextField(label: long, hint: long, helper: long),
    QuickChipRow<int>(options: [(1, long), (2, t('themeMidnight')), (3, t('themeIvory'))], selected: 1, onChanged: (_) {}),
    const MoneyText(1234567850, size: MoneySize.display),
    PriceDisplay(paise: 1450000, label: long, lowPaise: 1300000, highPaise: 1600000, taxIncluded: true),
    const Row(children: [AppAvatar(name: 'Ravi Kumar', verified: true), SizedBox(width: DsSpace.s2), Expanded(child: RatingStars(value: 4.5, count: 1280))]),
    DriverMiniCard(name: 'Ravi Kumar Yadav Shrivastava', rating: 4.8, trips: 1520, verified: true, vehicle: long),
    BidCard(driverName: 'Ravi Kumar', rating: 4.6, trips: 320, verified: true, pricePaise: 1450000, etaMinutes: 25, tags: BidTag.values, note: long, onAccept: () {}, onCounter: () {}),
    StatusTimelineV2(steps: [TimelineStepV2(long, time: '10:30'), TimelineStepV2(t('themeMidnight')), TimelineStepV2(t('themeIvory'))], current: 1),
    const RouteRibbon(from: 'Bhiwandi Warehouse Complex', to: 'Jawaharlal Nehru Port', distanceKm: 48),
  ]);
}

void main() {
  const widths = [320.0, 360.0, 600.0];
  // English, Hindi first, the longest scripts (Tamil, Kannada) and right to left (Urdu).
  const langs = [AppLanguage.english, AppLanguage.hindi, AppLanguage.tamil, AppLanguage.kannada, AppLanguage.urdu];
  for (final lang in langs) {
    for (final w in widths) {
      testWidgets('${lang.name} at ${w.toInt()} wide: every look, 2.0x text, no overflow', (t) async {
        t.view.physicalSize = Size(w, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        languageNotifier.value = lang;
        addTearDown(() => languageNotifier.value = AppLanguage.english);
        for (final style in ThemeStyle.values) {
          for (final b in Brightness.values) {
            await t.pumpWidget(LanguageScope(
              notifier: languageNotifier,
              child: MaterialApp(
                themeAnimationDuration: Duration.zero,
                theme: AppTheme.build(b, style: style),
                builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: Directionality(textDirection: lang.textDirection, child: child!)),
                home: Scaffold(
                  body: gallery(lang),
                  bottomNavigationBar: AppBottomNav(
                    items: const [AppNavItem(icon: Icons.home_outlined, label: 'Home'), AppNavItem(icon: Icons.receipt_long_outlined, label: 'Bookings', badge: 12), AppNavItem(icon: Icons.person_outline, label: 'Account')],
                    index: 0,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ));
            // Scroll through the whole list so every item lays out.
            await t.drag(find.byKey(const ValueKey('gallery')), const Offset(0, -20000));
            await t.pump();
            expect(t.takeException(), isNull, reason: '${lang.name} $w $style $b');
          }
        }
      });
    }
  }

  testWidgets('avatar: initials, Verified only when asked, and one spoken label', (t) async {
    expect(AppAvatar.initials('Ravi Kumar Yadav'), 'RY');
    expect(AppAvatar.initials('  ravi '), 'R');
    expect(AppAvatar.initials(''), '?');
    expect(AppAvatar.initials('रवि कुमार'), 'रक');
    final h = t.ensureSemantics();
    await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: const Scaffold(body: Column(children: [AppAvatar(name: 'Asha'), AppAvatar(name: 'Ravi', verified: true)])))));
    expect(find.bySemanticsLabel('Asha'), findsOneWidget);
    expect(find.bySemanticsLabel('Ravi, verified'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    h.dispose();
  });

  testWidgets('rating stars: halves, clamped, spoken as "out of 5"', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: const Scaffold(body: Column(children: [RatingStars(value: 3.5, count: 12), RatingStars(value: 9), RatingStars(value: double.nan)])))));
    expect(find.byIcon(Icons.star_half_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('3.5 out of 5 (12)'), findsOneWidget);
    expect(find.bySemanticsLabel('5.0 out of 5'), findsOneWidget);
    expect(find.bySemanticsLabel('0.0 out of 5'), findsOneWidget);
    h.dispose();
  });

  testWidgets('price display: range only when low <= high, tax note when asked', (t) async {
    await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: const Scaffold(body: Column(children: [PriceDisplay(paise: 1450000, lowPaise: 1300000, highPaise: 1600000, taxIncluded: true), PriceDisplay(paise: 500, lowPaise: 900, highPaise: 100)])))));
    expect(find.text(MoneyText.format(1450000)), findsOneWidget);
    expect(find.textContaining('Fair range'), findsOneWidget);
    expect(find.text('Tax included'), findsOneWidget);
  });
}
