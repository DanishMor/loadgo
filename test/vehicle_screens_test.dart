import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/vehicles/vehicle_catalog.dart';
import 'package:transport_app/core/vehicles/vehicle_screens.dart';
import 'package:transport_app/core/vehicles/what_fits.dart';

/// E17: what-fits logic, and the catalog, spec, compare and what-fits screens in every state, size and direction.
void main() {
  final all = VehicleCatalog.parse(File(VehicleCatalog.asset).readAsStringSync());
  VehicleSpec v(String id) => VehicleCatalog.byId(all, id)!;

  Widget host(Widget child, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
        notifier: ValueNotifier(lang),
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(textDirection: lang.textDirection, child: w!),
          ),
          home: child,
        ),
      );

  group('what fits', () {
    test('the smallest vehicle that carries the weight comes first', () {
      expect(whatFits(all, const FitRequest(tons: 3)).first.id, 'lcv_14ft');
      expect(whatFits(all, const FitRequest(tons: 0.01)).first.id, 'bike');
      expect(whatFits(all, const FitRequest(tons: 20)).first.maxTons, greaterThanOrEqualTo(20));
    });

    test('space and the longest item push it to a bigger vehicle', () {
      final byWeight = whatFits(all, const FitRequest(tons: 1)).first;
      final bySpace = whatFits(all, const FitRequest(tons: 1, volumeCft: 600)).first;
      expect(usableCft(bySpace), greaterThanOrEqualTo(600 * packingMargin));
      expect(usableCft(bySpace), greaterThan(usableCft(byWeight)));
      expect(whatFits(all, const FitRequest(tons: 1, longestFt: 20)).first.lengthFt, greaterThanOrEqualTo(20));
    });

    test('liquids go only in a tanker, cars only on a carrier, and special bodies are not offered for plain goods', () {
      expect(whatFits(all, const FitRequest(tons: 10, goods: 'liquids')).map((x) => x.id), ['tanker']);
      expect(whatFits(all, const FitRequest(tons: 10, goods: 'vehicles')).map((x) => x.id), ['car_carrier']);
      final plain = whatFits(all, const FitRequest(tons: 10)).map((x) => x.id);
      expect(plain, isNot(contains('tanker')));
      expect(plain, isNot(contains('car_carrier')));
      expect(plain, isNot(contains('hydra_crane')));
    });

    test('goods that match come first; nothing fits a load that is too heavy; bad input gives nothing', () {
      expect(whatFits(all, const FitRequest(tons: 5, goods: 'coldchain')).first.id, 'reefer');
      expect(whatFits(all, const FitRequest(tons: 80)), isEmpty);
      expect(whatFits(all, const FitRequest(tons: 0)), isEmpty);
      expect(whatFits(all, const FitRequest(tons: double.nan)), isEmpty);
      expect(whatFits(all, const FitRequest(tons: 2, volumeCft: -1)), isEmpty);
    });
  });

  test('numbers are short: 4.0 is 4, 2.5 stays 2.5, 19.4 stays 19.4', () {
    expect(fmtNum(4), '4');
    expect(fmtNum(2.5), '2.5');
    expect(fmtNum(19.4), '19.4');
    expect(fmtNum(0.02), '0.02');
  });

  testWidgets('catalog: a skeleton while loading, then the list with the approximate note', (t) async {
    await t.pumpWidget(host(VehicleCatalogScreen(load: () => Future.delayed(const Duration(milliseconds: 50), () => all))));
    expect(find.byKey(const ValueKey('vcList')), findsNothing);
    await t.pump(const Duration(milliseconds: 60));
    await t.pump();
    expect(find.byKey(const ValueKey('vcList')), findsOneWidget);
    expect(find.text(T.get('vcuApprox', AppLanguage.english)), findsOneWidget);
    expect(find.byKey(const ValueKey('vc_bike')), findsOneWidget);
  });

  testWidgets('catalog: an empty or broken asset shows a calm error with retry that loads again', (t) async {
    var calls = 0;
    await t.pumpWidget(host(VehicleCatalogScreen(load: () async => ++calls == 1 ? const <VehicleSpec>[] : all)));
    await t.pumpAndSettle();
    expect(find.text(T.get('vcuLoadError', AppLanguage.english)), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vcRetry')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('vcList')), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('catalog: compare appears at 2 ticks, a 4th tick is refused, and the compare screen lists them', (t) async {
    await t.pumpWidget(host(VehicleCatalogScreen(load: () async => all)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('vcCompareGo')), findsNothing);
    Future<void> tick(String id) async {
      final box = find.byKey(ValueKey('vcCmp_$id'));
      await t.scrollUntilVisible(box, 120, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.tap(box);
      await t.pump();
    }

    await tick('bike');
    await tick('auto_3w');
    expect(find.byKey(const ValueKey('vcCompareGo')), findsOneWidget);
    await tick('e_loader');
    await tick('mini_truck');
    expect(find.text(T.get('vcuCompareMax', AppLanguage.english)), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vcCompareGo')));
    await t.pumpAndSettle();
    expect(find.text(T.get('vcuCompareTitle', AppLanguage.english)), findsOneWidget);
    expect(find.byType(VehicleCompareScreen), findsOneWidget);
    expect(find.text(T.get('vc_mini_truck', AppLanguage.english)), findsNothing);
  });

  testWidgets('spec sheet: sizes, open top, a crane shows what it lifts, pick only when asked', (t) async {
    await t.pumpWidget(host(VehicleSpecScreen(spec: v('truck_6w'))));
    await t.pumpAndSettle();
    expect(find.text(T.get('vcuOpenTop', AppLanguage.english)), findsOneWidget);
    expect(find.text(T.get('vcWhen_truck_6w', AppLanguage.english)), findsOneWidget);
    expect(find.byKey(const ValueKey('vcPick')), findsNothing);
    await t.scrollUntilVisible(find.byType(SizeComparison), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byType(SizeComparison), findsOneWidget);

    await t.pumpWidget(host(VehicleSpecScreen(spec: v('hydra_crane'))));
    await t.pumpAndSettle();
    expect(find.textContaining(T.get('vcuLifts', AppLanguage.english)), findsWidgets);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await t.pumpAndSettle();
    expect(find.byType(SizeComparison), findsNothing);
    expect(find.text(T.get('vcuApprox', AppLanguage.english)), findsOneWidget);

    VehicleSpec? picked;
    await t.pumpWidget(host(VehicleSpecScreen(spec: v('lcv_14ft'), onPick: (x) => picked = x)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('vcPick')));
    expect(picked?.id, 'lcv_14ft');
  });

  testWidgets('what fits: a missing weight is explained; a good one suggests the best fit; too heavy says so', (t) async {
    await t.pumpWidget(host(WhatFitsScreen(all: all)));
    await t.tap(find.byKey(const ValueKey('vcFitGo')));
    await t.pump();
    expect(find.text(T.get('vcuFitBadWeight', AppLanguage.english)), findsOneWidget);

    await t.enterText(find.descendant(of: find.byKey(const ValueKey('vcFitWeight')), matching: find.byType(EditableText)), '3');
    await t.tap(find.byKey(const ValueKey('vcFitGo')));
    await t.pump();
    expect(find.text(T.get('vcuFitBest', AppLanguage.english)), findsOneWidget);
    expect(find.byKey(const ValueKey('vc_lcv_14ft')), findsOneWidget);

    await t.enterText(find.descendant(of: find.byKey(const ValueKey('vcFitWeight')), matching: find.byType(EditableText)), '90');
    await t.tap(find.byKey(const ValueKey('vcFitGo')));
    await t.pump();
    expect(find.byKey(const ValueKey('vcFitNone')), findsOneWidget);
  });

  test('the size picture fits the person, car, door and the longest vehicle in the width', () {
    for (final s in all.where((x) => !x.lifts)) {
      const size = Size(288, 150);
      final scale = SizeComparisonPainter.scaleFor(size, s.lengthFt, s.open ? 2 : s.heightFt);
      final used = (s.lengthFt + SizeComparisonPainter.person.$1 + SizeComparisonPainter.car.$1 + SizeComparisonPainter.door.$1 + SizeComparisonPainter.gapFt * 4) * scale;
      expect(used, lessThanOrEqualTo(size.width + 0.01), reason: s.id);
    }
  });

  for (final (lang, b, scale) in [
    (AppLanguage.hindi, Brightness.light, 2.0),
    (AppLanguage.urdu, Brightness.dark, 2.0),
    (AppLanguage.tamil, Brightness.dark, 1.3),
  ]) {
    testWidgets('no overflow at 320 dp: ${lang.name}, ${b.name}, ${scale}x', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      for (final screen in <Widget>[
        VehicleCatalogScreen(load: () async => all),
        VehicleSpecScreen(spec: v('box_32ft_mxl'), onPick: (_) {}),
        VehicleSpecScreen(spec: v('hydra_crane')),
        VehicleCompareScreen(vehicles: [v('bike'), v('container_40ft'), v('reefer')]),
        WhatFitsScreen(all: all),
      ]) {
        await t.pumpWidget(host(screen, lang: lang, b: b, scale: scale));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: screen.runtimeType.toString());
      }
    });
  }

  testWidgets('TalkBack: cards open by name, the compare tick says what it does, the picture is one sentence', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(host(VehicleCatalogScreen(load: () async => all)));
    await t.pumpAndSettle();
    final name = T.get('vc_bike', AppLanguage.english);
    expect(find.bySemanticsLabel(RegExp(RegExp.escape(trfFor('vcuOpen', name)))), findsWidgets);
    expect(find.bySemanticsLabel(RegExp(RegExp.escape(trfFor('vcuPickCompare', name)))), findsOneWidget);
    await t.pumpWidget(host(VehicleSpecScreen(spec: v('lcv_14ft'))));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byType(SizeComparison), 200, scrollable: find.byType(Scrollable).first);
    expect(find.bySemanticsLabel(RegExp('^${RegExp.escape(T.get('vcuSizeSay', AppLanguage.english).split('{').first)}')), findsOneWidget);
    handle.dispose();
  });
}

String trfFor(String key, String name) => T.get(key, AppLanguage.english).replaceAll('{name}', name);
