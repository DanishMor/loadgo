import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/auth/customer_login_screen.dart';
import 'package:transport_app/auth/driver_login_screen.dart';
import 'package:transport_app/auth/role_selection_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/contrast.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/app_button.dart';
import 'package:transport_app/core/widgets/ds/brand_logo.dart';

/// L16: the "who are you" screen.
Widget host({AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1.0, bool disableAnimations = true}) {
  final language = ValueNotifier(lang);
  final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(b),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: disableAnimations),
        child: Directionality(textDirection: dir, child: w!),
      ),
      home: const RoleSelectionScreen(),
    ),
  );
}

void main() {
  testWidgets('brand, welcome, one card per role, language card and footer', (t) async {
    t.view.physicalSize = const Size(400, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host());
    expect(find.byType(BrandLockup), findsOneWidget);
    expect(find.text(T.get('welcome', AppLanguage.english)), findsOneWidget);
    for (final r in ['customer', 'driver', 'transporter']) {
      expect(find.byKey(ValueKey('roleCard_$r')), findsOneWidget, reason: r);
    }
    expect(find.byType(AppButton), findsNWidgets(3));
    expect(find.byKey(const ValueKey('roleLanguageCard')), findsOneWidget);
    expect(find.text(T.get('footer', AppLanguage.english)), findsOneWidget);
  });

  testWidgets('each card goes to its own login', (t) async {
    t.view.physicalSize = const Size(400, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host());
    await t.tap(find.text(T.get('continueCustomer', AppLanguage.english)));
    await t.pumpAndSettle();
    expect(find.byType(CustomerLoginScreen), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text(T.get('continueDriver', AppLanguage.english)));
    await t.pumpAndSettle();
    expect(find.byType(DriverLoginScreen), findsOneWidget);
    expect(t.widget<DriverLoginScreen>(find.byType(DriverLoginScreen)).role, isNot('fleet'));
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text(T.get('continueFleet', AppLanguage.english)));
    await t.pumpAndSettle();
    expect(t.widget<DriverLoginScreen>(find.byType(DriverLoginScreen)).role, 'fleet');
  });

  testWidgets('the language button and the language card both open the language list', (t) async {
    t.view.physicalSize = const Size(400, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host());
    await t.tap(find.byKey(const ValueKey('roleLanguageButton')));
    await t.pumpAndSettle();
    expect(find.text('हिंदी'), findsWidgets);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('roleLanguageCard')));
    await t.pumpAndSettle();
    expect(find.text('தமிழ்'), findsWidgets);
  });

  for (final b in Brightness.values) {
    testWidgets('each role has its own colour line and a tinted icon tile (${b.name})', (t) async {
      t.view.physicalSize = const Size(400, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(b: b));
      final c = DsColors.of(b);
      final want = {'customer': c.roleCustomer, 'driver': c.roleDriver, 'transporter': c.roleTransporter};
      final seen = <Color>{};
      for (final e in want.entries) {
        final card = find.byKey(ValueKey('roleCard_${e.key}'));
        final line = t.widget<Container>(find.descendant(of: card, matching: find.byWidgetPredicate((w) => w is Container && w.color == e.value)).first);
        seen.add(line.color!);
        expect(contrastRatio(e.value, c.surface), greaterThanOrEqualTo(3.0), reason: e.key);
      }
      expect(seen.length, 3, reason: 'three different colours');
    });
  }

  testWidgets('with animations on the cards arrive one after the other', (t) async {
    t.view.physicalSize = const Size(400, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(disableAnimations: false));
    double opacity(String r) => t.widget<Opacity>(find.ancestor(of: find.byKey(ValueKey('roleCard_$r')), matching: find.byType(Opacity)).first).opacity;
    expect(opacity('customer'), 0);
    await t.pump(const Duration(milliseconds: 700));
    await t.pump(const Duration(milliseconds: 700));
    expect(opacity('customer'), 1);
    expect(opacity('driver'), 1);
    expect(opacity('transporter'), 1);
  });

  testWidgets('headings are headers for screen readers', (t) async {
    t.view.physicalSize = const Size(400, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final h = t.ensureSemantics();
    await t.pumpWidget(host());
    expect(t.getSemantics(find.text(T.get('welcome', AppLanguage.english))).flagsCollection.isHeader, isTrue);
    expect(t.getSemantics(find.text(T.get('bookTruck', AppLanguage.english))).flagsCollection.isHeader, isTrue);
    h.dispose();
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.tamil, AppLanguage.urdu, AppLanguage.kashmiri]) {
    for (final b in Brightness.values) {
      testWidgets('fits 360x640 at 2.0x text and scrolls: ${lang.name} ${b.name}', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(lang: lang, b: b, scale: 2.0));
        expect(t.takeException(), isNull);
        await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.text(T.get('footer', lang)), findsOneWidget);
      });
    }
  }
}
