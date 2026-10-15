import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/auth/splash_screen.dart';
import 'package:transport_app/core/app_info.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/contrast.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/brand_logo.dart';

/// L15: the splash screen.
Widget host({AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1.0, bool disableAnimations = false, bool lowEnd = false}) {
  final language = ValueNotifier(lang);
  final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(b, lowEnd: lowEnd),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: disableAnimations),
        child: Directionality(textDirection: dir, child: w!),
      ),
      home: const SplashView(),
    ),
  );
}

void main() {
  testWidgets('shows the mark, the name with the number apart, the tagline and a progress bar', (t) async {
    await t.pumpWidget(host());
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(LogoMark), findsOneWidget);
    expect(t.widget<LogoMark>(find.byType(LogoMark)).variant, LogoVariant.reversed);
    expect(find.byType(Wordmark), findsOneWidget);
    expect(find.text(AppInfo.tagline), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('the pieces arrive one after the other (mark, then name, then tagline)', (t) async {
    await t.pumpWidget(host());
    double opacityOf(Finder f) => t.widget<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity)).first).opacity;
    expect(opacityOf(find.byType(LogoMark)), lessThan(0.2));
    await t.pump(const Duration(milliseconds: 100));
    final mark100 = opacityOf(find.byType(LogoMark));
    expect(mark100, greaterThan(0));
    await t.pump(const Duration(milliseconds: 700));
    await t.pump(const Duration(milliseconds: 600));
    expect(opacityOf(find.byType(Wordmark)), 1);
    expect(opacityOf(find.text(AppInfo.tagline)), 1);
  });

  for (final mode in ['remove animations', 'Low-end mode']) {
    testWidgets('with $mode everything is there at once', (t) async {
      addTearDown(() => DsMotion.lowEnd = false);
      await t.pumpWidget(host(disableAnimations: mode == 'remove animations', lowEnd: mode == 'Low-end mode'));
      expect(find.byType(Wordmark), findsOneWidget);
      expect(find.ancestor(of: find.text(AppInfo.tagline), matching: find.byType(Opacity)), findsNothing);
    });
  }

  testWidgets('the tagline and the text on the gradient are readable (4.5:1)', (t) async {
    for (final c in DsHero.colors) {
      expect(contrastRatio(DsBrand.white, c), greaterThanOrEqualTo(4.5));
    }
    await t.pumpWidget(host());
    await t.pump(const Duration(seconds: 1));
    expect(t.widget<Text>(find.text(AppInfo.tagline)).style!.color, DsBrand.white);
  });

  testWidgets('screen readers hear the name and the tagline once', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(host());
    await t.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel('${AppInfo.name}. ${AppInfo.tagline}'), findsOneWidget);
    h.dispose();
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.tamil, AppLanguage.urdu]) {
    for (final b in Brightness.values) {
      testWidgets('fits 360x640 at 2.0x text: ${lang.name} ${b.name}', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(lang: lang, b: b, scale: 2.0));
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
        expect(find.text(T.get('tagline', lang)), findsOneWidget);
      });
    }
  }

  testWidgets('a very short screen scrolls instead of overflowing', (t) async {
    t.view.physicalSize = const Size(360, 300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(scale: 2.0));
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  });
}
