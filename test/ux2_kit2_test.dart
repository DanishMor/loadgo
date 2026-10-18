import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/feedback_kit.dart';
import 'package:transport_app/core/widgets/ds/haptics.dart';
import 'package:transport_app/core/widgets/ds/sheet_kit.dart';

/// U7, U8: sheets, quick chips, skeleton list, quiet hours, sound rule, heads-up banner.
Widget host(Widget child, {Brightness b = Brightness.light, double scale = 1.0, AppLanguage lang = AppLanguage.english}) {
  final language = ValueNotifier(lang);
  final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(b),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: dir, child: w!),
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Haptics.enabled.value = true;
    DsMotion.lowEnd = false;
    FeedbackKit.quiet = QuietHours.defaults;
  });

  test('quiet hours wrap past midnight and an equal start and end is empty', () {
    const q = QuietHours();
    expect(q.contains(DateTime(2030, 1, 1, 23, 0)), isTrue);
    expect(q.contains(DateTime(2030, 1, 1, 5, 59)), isTrue);
    expect(q.contains(DateTime(2030, 1, 1, 6, 0)), isFalse);
    expect(q.contains(DateTime(2030, 1, 1, 12, 0)), isFalse);
    expect(q.contains(DateTime(2030, 1, 1, 22, 0)), isTrue);
    const day = QuietHours(startMinute: 13 * 60, endMinute: 14 * 60);
    expect(day.contains(DateTime(2030, 1, 1, 13, 30)), isTrue);
    expect(day.contains(DateTime(2030, 1, 1, 14, 0)), isFalse);
    expect(const QuietHours(startMinute: 0, endMinute: 0).contains(DateTime(2030)), isFalse);
  });

  test('quiet hours are saved on the phone and bad values fall back to the default', () async {
    await const QuietHours(startMinute: 60, endMinute: 120).save();
    final q = await QuietHours.load();
    expect((q.startMinute, q.endMinute), (60, 120));
    SharedPreferences.setMockInitialValues({'quiet_start': 99999, 'quiet_end': 5});
    expect((await QuietHours.load()).startMinute, 22 * 60);
  });

  test('the sound plays by day, and not in quiet hours, Low-end mode or with touch feedback off', () async {
    var plays = 0;
    FeedbackKit.soundPlayer = () async => plays++;
    FeedbackKit.clock = () => DateTime(2030, 1, 1, 12);
    expect(await FeedbackKit.alert(), isTrue);
    FeedbackKit.clock = () => DateTime(2030, 1, 1, 23);
    expect(await FeedbackKit.alert(), isFalse);
    FeedbackKit.clock = () => DateTime(2030, 1, 1, 12);
    DsMotion.lowEnd = true;
    expect(await FeedbackKit.alert(), isFalse);
    DsMotion.lowEnd = false;
    Haptics.enabled.value = false;
    expect(await FeedbackKit.alert(), isFalse);
    expect(plays, 1);
    Haptics.enabled.value = true;
    FeedbackKit.soundPlayer = () async => throw StateError('no sound device');
    expect(await FeedbackKit.alert(), isFalse); // never throws
  });

  testWidgets('QuickChipRow selects, and clears when clearable', (t) async {
    String? sel = 'a';
    await t.pumpWidget(host(StatefulBuilder(builder: (c, set) => QuickChipRow<String>(options: const [('a', 'Alpha'), ('b', 'Beta')], selected: sel, clearable: true, onChanged: (v) => set(() => sel = v)))));
    await t.tap(find.text('Beta'));
    await t.pump();
    expect(sel, 'b');
    await t.tap(find.text('Beta'));
    await t.pump();
    expect(sel, isNull);
  });

  testWidgets('showAppSheet shows a title, content and closes with the close button', (t) async {
    await t.pumpWidget(host(Builder(builder: (c) => TextButton(onPressed: () => showAppSheet<void>(c, title: 'Pick', child: const Text('inside')), child: const Text('open')))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Pick'), findsOneWidget);
    expect(find.text('inside'), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.text('inside'), findsNothing);
  });

  testWidgets('the heads-up banner shows, runs onTap once, and goes away by itself', (t) async {
    var taps = 0;
    await t.pumpWidget(host(Builder(builder: (c) => TextButton(onPressed: () => showHeadsUp(c, title: 'New load', body: 'Delhi to Jaipur', seconds: 2, onTap: () => taps++), child: const Text('go')))));
    await t.tap(find.text('go'));
    await t.pump();
    expect(find.text('New load'), findsOneWidget);
    await t.tap(find.text('New load'));
    await t.pump();
    expect(taps, 1);
    expect(find.text('New load'), findsNothing);
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    expect(find.text('New load'), findsNothing);
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.urdu]) {
    for (final b in Brightness.values) {
      testWidgets('chips, skeletons and banner fit 360x640 at 2.0x: ${lang.name} ${b.name}', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(
          ListView(children: [
            QuickChipRow<int>(options: const [(1, 'Best price'), (2, 'Nearest'), (3, 'Top rated')], selected: 1, onChanged: (_) {}),
            const SkeletonList(),
            HeadsUpBanner(title: 'New load near you', body: 'Delhi to Jaipur, 281 km', onDismiss: () {}),
          ]),
          b: b,
          scale: 2.0,
          lang: lang,
        ));
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
      });
    }
  }
}
