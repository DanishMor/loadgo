import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/theme/app_theme.dart';

/// MASTER-6 Task 40.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('low-end mode is off by default, saved on the device, and survives a reload', () async {
    await LowEndMode.load();
    expect(LowEndMode.isOn, isFalse);
    await LowEndMode.set(true);
    LowEndMode.notifier.value = false;
    await LowEndMode.load();
    expect(LowEndMode.isOn, isTrue);
    await LowEndMode.set(false);
  });

  testWidgets('with low-end on, a page opens with no slide and no ripple', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(navigatorKey: nav, theme: AppTheme.build(Brightness.light, lowEnd: true), home: const Text('a')));
    nav.currentState!.push<void>(MaterialPageRoute(builder: (_) => const Text('b')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    // No slide: the new page sits at the left edge of the screen as soon as it is built.
    expect(t.getTopLeft(find.text('b')).dx, 0);
    expect(find.text('b'), findsOneWidget);
    expect(AppTheme.build(Brightness.light, lowEnd: true).splashFactory, NoSplash.splashFactory);
    expect(AppTheme.build(Brightness.light).splashFactory, isNot(NoSplash.splashFactory));
  });

  test('the text scale limit is 2.0', () => expect(maxTextScale, 2.0));
}
