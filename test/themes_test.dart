import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/contrast.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/core/widgets/ds/status_badge.dart';

/// E7: Signature (Ivory), Midnight (true black, Gold) and Classic themes.
void main() {
  test('E13b: AppColors.primary keeps the old blue in Classic and follows Signature and Midnight, with readable text on it', () {
    addTearDown(() => AppPalette.currentColors = DsColors.light);
    for (final c in [DsColors.light, DsColors.dark, DsColors.signature, DsColors.midnight]) {
      AppPalette.currentColors = c;
      final classic = identical(c, DsColors.light) || identical(c, DsColors.dark);
      expect(AppColors.primary, classic ? DsLegacy.primary : c.primary);
      expect(contrastRatio(AppColors.onPrimary, AppColors.primary), greaterThanOrEqualTo(4.5));
    }
  });

  test('each look maps light and dark to its own colour set', () {
    expect(ThemeStyle.signature.colors(Brightness.light), same(DsColors.signature));
    expect(ThemeStyle.signature.colors(Brightness.dark), same(DsColors.midnight));
    expect(ThemeStyle.classic.colors(Brightness.light), same(DsColors.light));
    expect(ThemeStyle.classic.colors(Brightness.dark), same(DsColors.dark));
  });

  test('Classic is the default build, so the earlier look is unchanged', () {
    final t = AppTheme.build(Brightness.light);
    expect(t.scaffoldBackgroundColor, DsColors.light.bg);
    expect(t.extension<DsTheme>()!.colors, same(DsColors.light));
    expect(t.extension<AppPalette>(), same(AppPalette.light));
  });

  test('Signature is Ivory with a Gold action; Midnight is true black', () {
    final sig = AppTheme.build(Brightness.light, style: ThemeStyle.signature);
    expect(sig.scaffoldBackgroundColor, DsLuxe.ivory);
    expect(sig.colorScheme.secondary, DsLuxe.gold);
    expect(sig.extension<AppPalette>(), same(AppPalette.signature));
    final mid = AppTheme.build(Brightness.dark, style: ThemeStyle.signature);
    expect(mid.scaffoldBackgroundColor.toARGB32(), 0xFF000000);
    expect(mid.colorScheme.primary, DsLuxe.goldLight);
    expect(mid.extension<AppPalette>(), same(AppPalette.midnight));
  });

  test('designV3 OFF shows Classic to everyone; ON shows the chosen look', () {
    ThemeStore.style.value = ThemeStyle.signature;
    expect(ThemeStore.effective(designV3: false), ThemeStyle.classic);
    expect(ThemeStore.effective(designV3: true), ThemeStyle.signature);
    final spec = Features.registry.firstWhere((s) => s.key == FeatureKey.designV3);
    expect(spec.pilotOn && spec.normalOn, isTrue);
    expect(const Features().isOn(FeatureKey.designV3), isTrue);
    expect(const Features(flags: {FeatureKey.designV3: false}).isOn(FeatureKey.designV3), isFalse);
  });

  test('the look is kept on the device and a bad value falls back to Signature', () async {
    SharedPreferences.setMockInitialValues({'theme_style': 'classic', 'theme_mode': 'dark'});
    await ThemeStore.load();
    expect(ThemeStore.style.value, ThemeStyle.classic);
    expect(ThemeStore.mode.value, ThemeMode.dark);
    await ThemeStore.setStyle(ThemeStyle.signature);
    expect((await SharedPreferences.getInstance()).getString('theme_style'), 'signature');
    SharedPreferences.setMockInitialValues({'theme_style': 'neon'});
    await ThemeStore.load();
    expect(ThemeStore.style.value, ThemeStyle.signature);
  });

  testWidgets('components read the theme being shown (parity in every look)', (t) async {
    for (final style in ThemeStyle.values) {
      for (final b in Brightness.values) {
        late DsColors seen;
        await t.pumpWidget(MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: AppTheme.build(b, style: style),
          home: Scaffold(
            appBar: AppBar(title: const Text('Title')),
            body: Builder(builder: (context) {
              seen = context.ds;
              return Column(children: [
                const TextField(decoration: InputDecoration(labelText: 'Phone')),
                FilledButton(onPressed: () {}, child: const Text('Go')),
                OutlinedButton(onPressed: () {}, child: const Text('More')),
                const Card(child: ListTile(title: Text('Row'))),
                const StatusBadge(label: 'Delivered', tone: StatusTone.success),
                Switch(value: true, onChanged: (_) {}),
              ]);
            }),
          ),
        ));
        expect(t.takeException(), isNull, reason: '$style $b');
        expect(seen, same(style.colors(b)), reason: '$style $b');
        final s = statusStyle(StatusTone.success, b, seen);
        expect(s.bg, seen.successBg);
      }
    }
  });
}
