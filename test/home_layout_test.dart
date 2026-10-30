import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/home/home_customize_sheet.dart';
import 'package:transport_app/core/home/home_layout.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';

/// E21a: home sections registry (order, hidden, locked), its store on the phone and the arrange sheet.
void main() {
  const known = ['hero', 'trip', 'routes', 'promise', 'lrs'];
  const locked = {'hero'};
  HomeLayout defaults() => HomeLayout.parse(null, known, locked: locked, hiddenByDefault: {'lrs'});

  group('HomeLayout', () {
    test('defaults: known order, default-hidden sections hidden, locked never hidden', () {
      final d = defaults();
      expect(d.order, known);
      expect(d.visible, ['hero', 'trip', 'routes', 'promise']);
      expect(HomeLayout.parse(null, known, locked: locked, hiddenByDefault: {'hero'}).visible, contains('hero'));
    });

    test('parse drops unknown, repeated and wrong-typed ids, appends new sections, keeps the saved choice', () {
      final l = HomeLayout.parse({
        'order': ['promise', 'ghost', 'promise', 7, 'hero'],
        'hidden': ['trip', 'hero', 'ghost', null],
      }, known, locked: locked, hiddenByDefault: {'lrs'});
      expect(l.order, ['promise', 'hero', 'trip', 'routes', 'lrs']);
      expect(l.hidden, {'trip', 'lrs'});
      expect(HomeLayout.parse('junk', known).order, known);
      expect(HomeLayout.parse({'order': 'x'}, known).order, known);
    });

    test('a section shown on purpose stays shown when it was hidden by default', () {
      final l = HomeLayout.parse({'order': known, 'hidden': <String>[]}, known, hiddenByDefault: {'lrs'});
      expect(l.isHidden('lrs'), isFalse);
    });

    test('move puts a section at its new index; bad indexes change nothing; toggle skips locked ones', () {
      final d = defaults();
      expect(d.move(0, 3).order, ['trip', 'routes', 'promise', 'hero', 'lrs']);
      expect(d.move(4, 0).order, ['lrs', 'hero', 'trip', 'routes', 'promise']);
      expect(d.move(9, 0).order, known);
      expect(d.move(0, 5).order, known);
      expect(d.toggle('hero').visible, contains('hero'));
      expect(d.toggle('trip').isHidden('trip'), isTrue);
      expect(d.toggle('trip').toggle('trip').isHidden('trip'), isFalse);
      expect(d.toggle('ghost').order, known);
    });
  });

  group('HomeLayoutStore', () {
    test('saves per role, loads it back, reset and broken data give the defaults', () async {
      SharedPreferences.setMockInitialValues({});
      await HomeLayoutStore.save('customer', defaults().move(4, 0).toggle('trip'));
      final back = await HomeLayoutStore.load('customer', known, locked: locked, hiddenByDefault: {'lrs'});
      expect(back.order.first, 'lrs');
      expect(back.hidden, {'trip', 'lrs'});
      expect((await HomeLayoutStore.load('driver', known)).order, known);
      await HomeLayoutStore.reset('customer');
      expect((await HomeLayoutStore.load('customer', known)).order, known);
      SharedPreferences.setMockInitialValues({HomeLayoutStore.key('customer'): '{not json'});
      expect((await HomeLayoutStore.load('customer', known)).order, known);
    });
  });

  group('HomeCustomizeSheet', () {
    const labels = {'hero': 'hlDone', 'trip': 'hlReset', 'routes': 'hlMoveUp', 'promise': 'hlMoveDown', 'lrs': 'hlAlways'};
    String en(String k) => T.get(k, AppLanguage.english);

    Widget host(ValueChanged<HomeLayout?> got, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
          notifier: ValueNotifier(lang),
          child: MaterialApp(
            theme: AppTheme.build(b, style: ThemeStyle.signature),
            builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: lang.textDirection, child: w!)),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => got(await showHomeCustomizeSheet(context, layout: defaults(), defaults: defaults(), labels: labels)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

    testWidgets('switches hide sections, the locked one cannot be switched; Done returns the layout', (t) async {
      HomeLayout? result;
      await t.pumpWidget(host((l) => result = l));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text(en('hlAlways')), findsWidgets);
      expect(t.widget<SwitchListTile>(find.byKey(const ValueKey('hlSwitch_hero'))).onChanged, isNull);
      await t.tap(find.byKey(const ValueKey('hlSwitch_trip')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('hlSwitch_lrs')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('hlDone')));
      await t.pumpAndSettle();
      expect(result!.hidden, {'trip'});
    });

    testWidgets('TalkBack move actions reorder; Reset goes back to the defaults', (t) async {
      final sem = t.ensureSemantics();
      HomeLayout? result;
      await t.pumpWidget(host((l) => result = l));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      final node = t.getSemantics(find.byKey(const ValueKey('hl_hero')));
      final down = node.getSemanticsData().customSemanticsActionIds!.map(CustomSemanticsAction.getAction).firstWhere((a) => a!.label == en('hlMoveDown'))!;
      node.owner!.performAction(node.id, SemanticsAction.customAction, CustomSemanticsAction.getIdentifier(down));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('hlDone')));
      await t.pumpAndSettle();
      expect(result!.order.take(2), ['trip', 'hero']);

      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('hlSwitch_trip')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('hlReset')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('hlDone')));
      await t.pumpAndSettle();
      expect(result!.hidden, {'lrs'});
      sem.dispose();
    });

    for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
      testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
        t.view.physicalSize = const Size(320, 720);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host((_) {}, lang: lang, b: b, scale: 2));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text(T.get('hlCustomize', lang)), findsOneWidget);
      });
    }
  });
}
