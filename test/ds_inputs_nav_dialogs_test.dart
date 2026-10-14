import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/ds_strings.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/app_bottom_nav.dart';
import 'package:transport_app/core/widgets/ds/app_dialogs.dart';
import 'package:transport_app/core/widgets/ds/app_text_field.dart';
import 'package:transport_app/core/widgets/ds/app_top_bar.dart';
import 'package:transport_app/core/widgets/ds/otp_field.dart';

/// L9: inputs, the OTP field, app bar, bottom navigation, dialogs, sheets and snackbars.
Widget host(Widget child, {Brightness b = Brightness.light, double scale = 1.0, AppLanguage lang = AppLanguage.english, PreferredSizeWidget? appBar, Widget? bottom}) {
  final language = ValueNotifier(lang);
  final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(b),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: dir, child: w!)),
      home: Scaffold(appBar: appBar, bottomNavigationBar: bottom, body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
    ),
  );
}

void main() {
  group('strings', () {
    test('every ds string has 12 languages and the OTP label has both numbers', () {
      for (final e in dsStrings.entries) {
        expect(e.value.length, 12, reason: e.key);
        expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      }
      for (final s in dsStrings['dsOtpLabel']!) {
        expect(s.contains('{n}') && s.contains('{m}'), isTrue, reason: s);
      }
      for (final s in dsStrings['dsNewCount']!) {
        expect(s.contains('{n}'), isTrue, reason: s);
      }
      expect(T.get('dsOk', AppLanguage.hindi), 'ठीक है');
    });
  });

  group('OtpField', () {
    testWidgets('digits go into the boxes, the last one completes once, letters and extra digits are dropped', (t) async {
      final done = <String>[];
      final changed = <String>[];
      await t.pumpWidget(host(OtpField(fieldKey: const ValueKey('otpField'), onChanged: changed.add, onCompleted: done.add)));
      await t.enterText(find.byKey(const ValueKey('otpField')), '48a29');
      await t.pump();
      expect(find.text('4'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(done, isEmpty);
      await t.enterText(find.byKey(const ValueKey('otpField')), '4829137');
      await t.pump();
      expect(changed.last, '482913');
      expect(done, ['482913']);
      expect(find.text('7'), findsNothing);
    });

    testWidgets('backspace clears the last box; an external controller is honoured', (t) async {
      final c = TextEditingController(text: '123');
      await t.pumpWidget(host(OtpField(controller: c, fieldKey: const ValueKey('f'))));
      expect(find.text('3'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('f')), '12');
      await t.pump();
      expect(find.text('3'), findsNothing);
      expect(c.text, '12');
      c.clear();
      await t.pump();
      expect(find.text('1'), findsNothing);
    });

    testWidgets('six boxes by default, a different length works, boxes are at least 56 dp tall', (t) async {
      await t.pumpWidget(host(const OtpField()));
      final boxes = find.descendant(of: find.byType(OtpField), matching: find.byType(AnimatedContainer));
      expect(boxes, findsNWidgets(6));
      expect(t.getSize(boxes.first).height, greaterThanOrEqualTo(56));
      await t.pumpWidget(host(const OtpField(length: 4)));
      expect(find.descendant(of: find.byType(OtpField), matching: find.byType(AnimatedContainer)), findsNWidgets(4));
    });

    testWidgets('error turns every box red with a thicker border', (t) async {
      await t.pumpWidget(host(const OtpField(error: true)));
      final box = t.widget<AnimatedContainer>(find.descendant(of: find.byType(OtpField), matching: find.byType(AnimatedContainer)).first).decoration as BoxDecoration;
      final side = (box.border as Border).top;
      expect(side.color, DsColors.light.error);
      expect(side.width, 2);
    });

    testWidgets('the focus ring follows the typing (auto-advance)', (t) async {
      await t.pumpWidget(host(const OtpField(autofocus: true, fieldKey: ValueKey('f'))));
      await t.pump();
      Color ring(int i) {
        final box = t.widget<AnimatedContainer>(find.descendant(of: find.byType(OtpField), matching: find.byType(AnimatedContainer)).at(i)).decoration as BoxDecoration;
        return (box.border as Border).top.color;
      }

      expect(ring(0), DsColors.light.focus);
      await t.enterText(find.byKey(const ValueKey('f')), '12');
      await t.pump();
      expect(ring(2), DsColors.light.focus, reason: 'the third box is next');
      expect(ring(0), DsColors.light.primary, reason: 'a filled box is navy');
    });

    testWidgets('screen readers hear the progress in the language', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(OtpField(controller: TextEditingController(text: '12'))));
      expect(find.bySemanticsLabel('Verification code: 2 of 6 digits entered'), findsOneWidget);
      await t.pumpWidget(host(OtpField(controller: TextEditingController(text: '12')), lang: AppLanguage.hindi));
      expect(find.bySemanticsLabel('सत्यापन कोड: 6 में से 2 अंक डाले'), findsOneWidget);
      h.dispose();
    });

    for (final lang in [AppLanguage.urdu, AppLanguage.hindi, AppLanguage.english]) {
      for (final b in Brightness.values) {
        testWidgets('fits 360x640 at 2.0x text: ${lang.name} ${b.name}; digits stay left to right', (t) async {
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(host(OtpField(controller: TextEditingController(text: '123456')), b: b, scale: 2.0, lang: lang));
          expect(t.takeException(), isNull);
          final first = t.getTopLeft(find.text('1')).dx;
          final last = t.getTopLeft(find.text('6')).dx;
          expect(first, lessThan(last), reason: 'digit order never mirrors');
        });
      }
    }
  });

  group('CountdownController and OtpResendButton', () {
    testWidgets('counts down by the second, enables the button at zero, can restart', (t) async {
      final c = CountdownController();
      addTearDown(c.dispose);
      var sent = 0;
      await t.pumpWidget(host(OtpResendButton(countdown: c, onPressed: () => sent++)));
      expect(find.text('Resend OTP'), findsOneWidget);
      c.start(3);
      await t.pump();
      expect(find.textContaining('3'), findsOneWidget);
      expect(t.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
      await t.pump(const Duration(seconds: 1));
      expect(c.secondsLeft, 2);
      await t.pump(const Duration(seconds: 2));
      expect(c.running, isFalse);
      expect(t.widget<TextButton>(find.byType(TextButton)).onPressed, isNotNull);
      await t.tap(find.byType(TextButton));
      expect(sent, 1);
      c.start(60);
      await t.pump();
      expect(c.secondsLeft, 60);
      c.stop();
      await t.pump();
      expect(c.running, isFalse);
    });

    testWidgets('busy keeps it disabled even at zero', (t) async {
      final c = CountdownController();
      addTearDown(c.dispose);
      await t.pumpWidget(host(OtpResendButton(countdown: c, onPressed: () {}, busy: true)));
      expect(t.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    });
  });

  group('AppTextField', () {
    testWidgets('label above the box, hint inside, help below', (t) async {
      await t.pumpWidget(host(const AppTextField(label: 'Phone number', hint: '98765 43210', helper: 'We send an OTP', prefixText: '+91 ')));
      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('We send an OTP'), findsOneWidget);
      expect(t.getTopLeft(find.text('Phone number')).dy, lessThan(t.getTopLeft(find.byType(TextField)).dy));
    });

    testWidgets('an error shows an icon, the text, and the red border', (t) async {
      await t.pumpWidget(host(const AppTextField(label: 'Phone', error: 'Enter 10 digits')));
      expect(find.text('Enter 10 digits'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      final deco = t.widget<TextField>(find.byType(TextField)).decoration!;
      expect((deco.enabledBorder as OutlineInputBorder).borderSide.color, DsColors.light.error);
    });

    testWidgets('typing, formatters, max length and obscure work', (t) async {
      final c = TextEditingController();
      await t.pumpWidget(host(AppTextField(label: 'PIN', controller: c, maxLength: 4, obscure: true, keyboardType: TextInputType.number)));
      await t.enterText(find.byType(TextField), '123456');
      expect(c.text.length, 4);
      expect(t.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    });

    for (final b in Brightness.values) {
      testWidgets('multi-line and long label at 2.0x, ${b.name}', (t) async {
        await t.pumpWidget(host(const AppTextField(label: 'சரக்கு பற்றிய கூடுதல் விவரங்களை இங்கே எழுதுங்கள்', minLines: 3, maxLines: 5), b: b, scale: 2.0));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('AppTopBar', () {
    testWidgets('title, subtitle, spoken 48 dp back button, role line', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Builder(builder: (c) => Scaffold(body: Center(child: ElevatedButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(appBar: AppTopBar(title: 'Trips', subtitle: 'Delhi to Jaipur', role: 'driver')))), child: const Text('open'))))),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Delhi to Jaipur'), findsOneWidget);
      expect(t.getSize(find.byTooltip('Back')).width, greaterThanOrEqualTo(48));
      final line = t.widget<Container>(find.byWidgetPredicate((w) => w is Container && w.color == DsColors.light.roleDriver));
      expect(line.constraints?.maxHeight, 3);
      await t.tap(find.byTooltip('Back'));
      await t.pumpAndSettle();
      expect(find.text('Trips'), findsNothing);
    });

    testWidgets('no back button on a root screen, height grows with a subtitle and a role line', (t) async {
      await t.pumpWidget(host(const SizedBox(), appBar: const AppTopBar(title: 'Home')));
      expect(find.byTooltip('Back'), findsNothing);
      expect(const AppTopBar(title: 'a').preferredSize.height, kToolbarHeight);
      expect(const AppTopBar(title: 'a', subtitle: 'b', role: 'customer').preferredSize.height, 75);
    });

    testWidgets('a long title is cut with an ellipsis at 2.0x', (t) async {
      await t.pumpWidget(host(const SizedBox(), scale: 2.0, appBar: const AppTopBar(title: 'A very long screen title that cannot fit on one line', subtitle: 'and a long second line too')));
      expect(t.takeException(), isNull);
    });
  });

  group('AppBottomNav', () {
    final items = [
      const AppNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
      const AppNavItem(icon: Icons.local_shipping_outlined, label: 'Trips', badge: 3),
      const AppNavItem(icon: Icons.person_outline, label: 'Profile', badge: 120),
    ];

    testWidgets('labels always shown, badges counted and capped, taps report the index', (t) async {
      var index = 0;
      await t.pumpWidget(StatefulBuilder(builder: (c, set) => host(const SizedBox(), bottom: AppBottomNav(items: items, index: index, onChanged: (i) => set(() => index = i)))));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      await t.tap(find.text('Trips'));
      await t.pump();
      expect(index, 1);
    });

    testWidgets('a badge is spoken as "3 new"', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(const SizedBox(), bottom: AppBottomNav(items: items, index: 0, onChanged: (_) {})));
      expect(find.bySemanticsLabel(RegExp('3 new')), findsOneWidget);
      h.dispose();
    });

    test('2 to 5 tabs only', () {
      expect(() => AppBottomNav(items: items.take(1).toList(), index: 0, onChanged: (_) {}), throwsAssertionError);
    });

    for (final lang in [AppLanguage.tamil, AppLanguage.urdu]) {
      testWidgets('long labels fit at 2.0x in ${lang.name}', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(const SizedBox(), scale: 2.0, lang: lang, bottom: AppBottomNav(items: [
          const AppNavItem(icon: Icons.home_outlined, label: 'முகப்புப் பக்கம்'),
          const AppNavItem(icon: Icons.local_shipping_outlined, label: 'பயணங்கள் மற்றும் முன்பதிவுகள்'),
          const AppNavItem(icon: Icons.person_outline, label: 'என் சுயவிவரம்'),
        ], index: 0, onChanged: (_) {})));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('dialogs, sheets and snackbars', () {
    Widget launcher(void Function(BuildContext) go) => host(Builder(builder: (c) => ElevatedButton(onPressed: () => go(c), child: const Text('go'))));

    testWidgets('confirm returns true on confirm, false on cancel and on dismiss', (t) async {
      bool? result;
      await t.pumpWidget(launcher((c) async => result = await showConfirmDialog(c, title: 'Cancel booking?', message: 'The driver is told at once.')));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Cancel booking?'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(result, isTrue);
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(result, isFalse);
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(2, 2));
      await t.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('danger confirm is red; labels can be given; the words follow the language', (t) async {
      await t.pumpWidget(launcher((c) => showConfirmDialog(c, title: 'Delete?', confirmLabel: 'Delete', cancelLabel: 'Keep', danger: true)));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      final btn = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Delete'));
      expect(btn.style!.backgroundColor!.resolve({}), DsColors.light.error);
      expect(find.text('Keep'), findsOneWidget);
    });

    testWidgets('Hindi words on the default buttons', (t) async {
      await t.pumpWidget(host(Builder(builder: (c) => ElevatedButton(onPressed: () => showConfirmDialog(c, title: 'क्या आप पक्का हैं?'), child: const Text('go'))), lang: AppLanguage.hindi));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('पक्का करें'), findsOneWidget);
    });

    testWidgets('a sheet shows the title and the content and scrolls tall content', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(launcher((c) => showAppSheet<void>(c, title: 'Filters', builder: (_) => Column(children: [for (var i = 0; i < 40; i++) Text('row $i')]))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('row 0'), findsOneWidget);
      expect(t.getTopLeft(find.text('row 39')).dy, greaterThan(640), reason: 'below the fold until scrolled');
      await t.drag(find.text('row 0'), const Offset(0, -2000));
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.text('row 39')).dy, lessThan(640));
      expect(t.takeException(), isNull);
    });

    testWidgets('snackbars: tone, icon, action, one at a time', (t) async {
      var retried = 0;
      await t.pumpWidget(launcher((c) {
        showAppSnack(c, 'Saved', kind: SnackKind.success);
        showAppSnack(c, 'No internet', kind: SnackKind.error, onAction: () => retried++);
      }));
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('No internet'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await t.tap(find.text('Retry'));
      expect(retried, 1);
    });
  });
}
