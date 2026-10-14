import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/contrast.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/core/widgets/ds/app_button.dart';
import 'package:transport_app/core/widgets/ds/status_badge.dart';

/// L8: buttons, cards and status badges of the design system.
Widget host(Widget child, {Brightness b = Brightness.light, double scale = 1.0, TextDirection dir = TextDirection.ltr}) => MaterialApp(
      theme: AppTheme.build(b),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: dir, child: w!)),
      home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
    );

void main() {
  group('ensureContrast', () {
    test('keeps a colour that already reads and fixes one that does not', () {
      expect(ensureContrast(const Color(0xFF0F1B2D), const Color(0xFFFFFFFF)), const Color(0xFF0F1B2D));
      const pale = Color(0xFF12B76A); // the old success green: 2.6:1 on white
      expect(contrastRatio(pale, const Color(0xFFFFFFFF)), lessThan(4.5));
      final fixed = ensureContrast(pale, const Color(0xFFFFFFFF));
      expect(contrastRatio(fixed, const Color(0xFFFFFFFF)), greaterThanOrEqualTo(4.5));
      expect((fixed.g * 255).round(), greaterThan((fixed.r * 255).round()), reason: 'still a green');
    });

    test('goes lighter on a dark background and always returns an opaque colour', () {
      const dark = Color(0xFF16213A);
      final c = ensureContrast(const Color(0x80123A6B), dark);
      expect(contrastRatio(c, dark), greaterThanOrEqualTo(4.5));
      expect(c.a, 1.0);
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21, 0.01));
      expect(contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)), closeTo(1, 0.001));
    });
  });

  group('statusToneFor', () {
    test('every booking, load, payment and LR status has a tone, and they agree', () {
      for (final s in [BookingStatus.accepted, BookingStatus.driverArriving, BookingStatus.loading, BookingStatus.pickedUp, BookingStatus.inTransit, BookingStatus.unloading]) {
        expect(statusToneFor(s), StatusTone.progress, reason: s);
      }
      expect(statusToneFor(BookingStatus.delivered), StatusTone.success);
      expect(statusToneFor(BookingStatus.cancelled), StatusTone.danger);
      expect(statusToneFor(LoadStatus.open), StatusTone.neutral);
      expect(statusToneFor(LoadStatus.matched), StatusTone.progress);
      expect(statusToneFor(LoadStatus.closed), StatusTone.neutral);
      expect(statusToneFor(LoadStatus.awaitingApproval), StatusTone.attention);
      expect(statusToneFor(PaymentStatus.pending), StatusTone.attention);
      expect(statusToneFor(PaymentStatus.customerMarkedPaid), StatusTone.attention);
      expect(statusToneFor(PaymentStatus.driverConfirmed), StatusTone.success);
      expect(statusToneFor(LrStatus.issued), StatusTone.success);
      expect(statusToneFor(LrStatus.superseded), StatusTone.attention);
      expect(statusToneFor(LrStatus.cancelled), StatusTone.danger);
      for (final s in ['requested', 'approved', 'paid', 'rejected', 'reversed']) {
        expect(statusToneFor(s), isNot(StatusTone.neutral), reason: 'payout state $s');
      }
      expect(statusToneFor('paid'), StatusTone.success);
      expect(statusToneFor('rejected'), StatusTone.danger);
    });

    test('spelling, case and unknown words are handled', () {
      expect(statusToneFor('In Transit'), StatusTone.progress);
      expect(statusToneFor('PICKED-UP'), StatusTone.progress);
      expect(statusToneFor(null), StatusTone.neutral);
      expect(statusToneFor(''), StatusTone.neutral);
      expect(statusToneFor('something_new'), StatusTone.neutral);
    });

    test('every tone is readable (4.5:1) in light and dark', () {
      for (final b in Brightness.values) {
        for (final t in StatusTone.values) {
          final s = statusStyle(t, b);
          expect(contrastRatio(s.fg, s.bg), greaterThanOrEqualTo(4.5), reason: '${t.name} ${b.name}');
        }
      }
    });
  });

  group('StatusBadge', () {
    testWidgets('shows the label and an icon for the tone, in both modes', (t) async {
      for (final b in Brightness.values) {
        await t.pumpWidget(host(StatusBadge.forStatus('delivered', label: 'Delivered'), b: b));
        expect(find.text('Delivered'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
        await t.pumpWidget(host(const StatusBadge(label: 'Cancelled', tone: StatusTone.danger, showIcon: false), b: b));
        expect(find.byIcon(Icons.cancel_outlined), findsNothing);
      }
    });

    testWidgets('a long label wraps at 2.0x text and RTL without overflow', (t) async {
      await t.pumpWidget(host(const StatusBadge(label: 'ڈرائیور کا انتظار ہے، براہ کرم کچھ دیر ٹھہریں اور دوبارہ دیکھیں', tone: StatusTone.attention), scale: 2.0, dir: TextDirection.rtl));
      expect(t.takeException(), isNull);
    });

    testWidgets('the old StatusChip and ColorBadge keep their API and read in both modes', (t) async {
      for (final b in Brightness.values) {
        await t.pumpWidget(host(StatusChip(label: 'Online', color: AppColors.success), b: b));
        expect(find.text('Online'), findsOneWidget);
        expect(find.byType(ColorBadge), findsOneWidget);
        final text = t.widget<Text>(find.text('Online'));
        final bg = t.widget<Container>(find.descendant(of: find.byType(ColorBadge), matching: find.byType(Container))).decoration as BoxDecoration;
        expect(contrastRatio(text.style!.color!, bg.color!), greaterThanOrEqualTo(4.5), reason: b.name);
      }
    });
  });

  group('AppButton', () {
    testWidgets('primary is saffron with dark text and at least 48 dp', (t) async {
      var taps = 0;
      await t.pumpWidget(host(AppButton(label: 'Post load', onPressed: () => taps++)));
      final style = t.widget<ElevatedButton>(find.byType(ElevatedButton)).style!;
      expect(style.backgroundColor!.resolve({}), DsColors.light.accent);
      expect(style.foregroundColor!.resolve({}), DsColors.light.onAccent);
      expect(t.getSize(find.byType(ElevatedButton)).height, greaterThanOrEqualTo(48));
      await t.tap(find.text('Post load'));
      expect(taps, 1);
    });

    testWidgets('big (Driver Simple Mode) is 64 dp tall', (t) async {
      await t.pumpWidget(host(AppButton(label: 'Start trip', onPressed: () {}, big: true)));
      expect(t.getSize(find.byType(ElevatedButton)).height, DsSpace.tapBig);
    });

    testWidgets('each kind uses its own widget and colours', (t) async {
      await t.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
        AppButton(label: 'strong', onPressed: () {}, kind: AppButtonKind.strong),
        AppButton(label: 'danger', onPressed: () {}, kind: AppButtonKind.danger),
        AppButton(label: 'secondary', onPressed: () {}, kind: AppButtonKind.secondary),
        AppButton(label: 'tertiary', onPressed: () {}, kind: AppButtonKind.tertiary),
      ])));
      expect(find.byType(ElevatedButton), findsNWidgets(2));
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
      final danger = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'danger')).style!;
      expect(danger.backgroundColor!.resolve({}), DsColors.light.error);
      final strong = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'strong')).style!;
      expect(strong.backgroundColor!.resolve({}), DsColors.light.primary);
    });

    testWidgets('loading and a null handler both disable it; loading shows a spinner', (t) async {
      var taps = 0;
      await t.pumpWidget(host(AppButton(label: 'Save', onPressed: () => taps++, loading: true)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.tap(find.byType(ElevatedButton), warnIfMissed: false);
      expect(taps, 0);
      await t.pumpWidget(host(const AppButton(label: 'Save', onPressed: null)));
      expect(t.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    });

    testWidgets('exposes one button with its label to screen readers', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(AppButton(label: 'Pay now', onPressed: () {})));
      expect(find.bySemanticsLabel('Pay now'), findsOneWidget);
      h.dispose();
    });

    testWidgets('PrimaryButton is the same button', (t) async {
      await t.pumpWidget(host(PrimaryButton(label: 'Go', onPressed: () {}, icon: Icons.check)));
      expect(find.byType(AppButton), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    for (final b in Brightness.values) {
      testWidgets('long Tamil label fits 320 wide at 2.0x text (${b.name})', (t) async {
        await t.pumpWidget(host(AppButton(label: 'சரக்கை பதிவு செய்து ஓட்டுநர்களின் விலைகளைப் பாருங்கள்', onPressed: () {}), b: b, scale: 2.0));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('AppCard', () {
    testWidgets('uses the large radius token and a border, and taps', (t) async {
      var taps = 0;
      await t.pumpWidget(host(AppCard(onTap: () => taps++, child: const Text('Card body'))));
      final box = t.widget<Container>(find.descendant(of: find.byType(AppCard), matching: find.byType(Container)).first).decoration as BoxDecoration;
      expect(box.borderRadius, DsRadius.all(DsRadius.lg));
      expect(box.border, isNotNull);
      await t.tap(find.text('Card body'));
      expect(taps, 1);
    });
  });
}
