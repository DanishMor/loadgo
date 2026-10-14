import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';

/// L5: the Material 3 theme is built from the design tokens in both modes.
void main() {
  for (final b in Brightness.values) {
    final c = DsColors.of(b);
    final name = b.name;

    group('$name theme', () {
      final t = AppTheme.build(b);

      test('is Material 3 and uses the token colours', () {
        expect(t.useMaterial3, isTrue);
        expect(t.brightness, b);
        expect(t.colorScheme.primary, c.primary);
        expect(t.colorScheme.onPrimary, c.onPrimary);
        expect(t.colorScheme.secondary, c.accent);
        expect(t.colorScheme.error, c.error);
        expect(t.colorScheme.surface, c.surface);
        expect(t.colorScheme.onSurface, c.text);
        expect(t.colorScheme.outline, c.inputBorder);
        expect(t.scaffoldBackgroundColor, c.bg);
      });

      test('the palette extension carries the tokens (old AppColors keeps working)', () {
        final p = t.extension<AppPalette>()!;
        expect(p.bg, c.bg);
        expect(p.card, c.surface);
        expect(p.text, c.text);
        expect(p.muted, c.textMuted);
        expect(p.border, c.border);
        expect(identical(p, b == Brightness.dark ? AppPalette.dark : AppPalette.light), isTrue);
      });

      test('text theme follows the type scale', () {
        expect(t.textTheme.bodyLarge!.fontSize, 16);
        expect(t.textTheme.titleLarge!.fontSize, 20);
        expect(t.textTheme.headlineLarge!.fontSize, 24);
        expect(t.textTheme.bodySmall!.fontSize, 12);
        expect(t.textTheme.bodyLarge!.color, c.text);
      });

      test('buttons are at least 48 dp tall; the action is saffron with dark text', () {
        final filled = t.filledButtonTheme.style!;
        expect(filled.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
        expect(filled.backgroundColor!.resolve({}), c.accent);
        expect(filled.foregroundColor!.resolve({}), c.onAccent);
        expect(t.outlinedButtonTheme.style!.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
        expect(t.textButtonTheme.style!.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
        expect(t.iconButtonTheme.style!.minimumSize!.resolve({})!.width, greaterThanOrEqualTo(48));
      });

      test('inputs use the 3:1 border and a thicker focus ring', () {
        final i = t.inputDecorationTheme;
        expect((i.enabledBorder as OutlineInputBorder).borderSide.color, c.inputBorder);
        final focused = (i.focusedBorder as OutlineInputBorder).borderSide;
        expect(focused.color, c.focus);
        expect(focused.width, 2);
        expect((i.errorBorder as OutlineInputBorder).borderSide.color, c.error);
      });

      test('cards, sheets and dialogs use the radius and elevation tokens', () {
        final card = t.cardTheme.shape as RoundedRectangleBorder;
        expect(card.borderRadius, BorderRadius.circular(DsRadius.lg));
        expect(t.cardTheme.elevation, DsElevation.none);
        expect(t.dialogTheme.elevation, DsElevation.dialog);
        expect(t.bottomSheetTheme.elevation, DsElevation.sheet);
      });

      test('role accents are in the theme', () {
        final r = t.extension<RoleAccents>()!;
        expect(r.customer, c.roleCustomer);
        expect(r.driver, c.roleDriver);
        expect(r.transporter, c.roleTransporter);
        expect(r.forRole('driver', c.primary), c.roleDriver);
        expect(r.forRole('admin', c.primary), c.primary);
        expect(r.forRole(null, c.primary), c.primary);
      });
    });
  }

  test('dark scaffold is navy-tinted, not pure black', () {
    final bg = AppTheme.build(Brightness.dark).scaffoldBackgroundColor;
    expect(bg, isNot(const Color(0xFF000000)));
    expect((bg.b * 255).round(), greaterThan((bg.r * 255).round()));
  });

  test('Low-end mode: no ink splash, no page slide, and the motion tokens go to zero', () {
    addTearDown(() => DsMotion.lowEnd = false);
    final low = AppTheme.build(Brightness.light, lowEnd: true);
    expect(low.splashFactory, NoSplash.splashFactory);
    expect(low.pageTransitionsTheme.builders, isNotEmpty);
    expect(DsMotion.lowEnd, isTrue);
    final normal = AppTheme.build(Brightness.light);
    expect(DsMotion.lowEnd, isFalse);
    expect(normal.splashFactory, isNot(NoSplash.splashFactory));
  });

  test('RoleAccents lerps and copies', () {
    final a = RoleAccents(customer: DsColors.light.roleCustomer, driver: DsColors.light.roleDriver, transporter: DsColors.light.roleTransporter);
    final b = a.copyWith(driver: const Color(0xFF000000));
    expect(b.driver, const Color(0xFF000000));
    expect(b.customer, a.customer);
    expect(a.lerp(b, 0).driver, a.driver);
    expect(a.lerp(b, 1).driver, b.driver);
    expect(identical(a.lerp(null, 0.5), a), isTrue);
  });

  testWidgets('a themed screen builds in light and dark without a throw', (t) async {
    for (final b in Brightness.values) {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(b),
        home: Scaffold(
          appBar: AppBar(title: const Text('Load 20')),
          body: Column(children: [
            const TextField(decoration: InputDecoration(labelText: 'Phone')),
            FilledButton(onPressed: () {}, child: const Text('Go')),
            OutlinedButton(onPressed: () {}, child: const Text('More')),
            const Card(child: ListTile(title: Text('Row'))),
            Switch(value: true, onChanged: (_) {}),
            Checkbox(value: true, onChanged: (_) {}),
          ]),
        ),
      ));
      expect(t.takeException(), isNull);
      expect(find.text('Go'), findsOneWidget);
    }
  });
}
