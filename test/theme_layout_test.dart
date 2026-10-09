import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/auth/customer_login_screen.dart';
import 'package:transport_app/auth/driver_login_screen.dart';
import 'package:transport_app/auth/role_selection_screen.dart';
import 'package:transport_app/core/notifications/notifications_screen.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/settings/account_deletion_screen.dart';
import 'package:transport_app/core/settings/help_screen.dart';
import 'package:transport_app/core/settings/legal_screens.dart';
import 'package:transport_app/core/settings/onboarding_screen.dart';
import 'package:transport_app/core/settings/settings_screen.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/customer/customer_home_screen.dart';
import 'package:transport_app/customer/post_load_screen.dart';
import 'package:transport_app/driver/driver_home_screen.dart';
import 'package:transport_app/driver/wallet_screen.dart';

import 'test_utils.dart';

void main() {
  setUp(() async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    await db.collection('users').doc('u1').set({'role': 'customer', 'name': 'Asha'});
    Backend.useFakes(db: db, uid: () => 'u1', auth: () => MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1', phoneNumber: '+919999999999')));
    SharedPreferences.setMockInitialValues({});
    AppPalette.current = AppPalette.light;
    ThemeStore.mode.value = ThemeMode.system;
  });

  test('palette flips with the theme and the dark palette keeps text readable', () {
    AppPalette.current = AppPalette.light;
    final lightText = AppColors.title;
    AppPalette.current = AppPalette.dark;
    expect(AppColors.title, isNot(lightText));
    expect(AppColors.background, AppPalette.dark.bg);
    // text on the page and on a card needs at least 4.5:1 (WCAG AA)
    double lum(Color c) => c.computeLuminance();
    double ratio(Color a, Color b) {
      final x = lum(a) + 0.05, y = lum(b) + 0.05;
      return x > y ? x / y : y / x;
    }

    for (final p in [AppPalette.light, AppPalette.dark]) {
      for (final bg in [p.bg, p.card]) {
        expect(ratio(p.text, bg), greaterThan(4.5));
        expect(ratio(p.strong, bg), greaterThan(4.5));
        expect(ratio(p.muted, bg), greaterThan(4.5));
      }
    }
  });

  test('every IconButton has a tooltip (screen readers) and no old hard-coded light greys remain', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      for (final m in RegExp(r'\bIconButton\(').allMatches(s)) {
        var depth = 1, j = m.end;
        while (depth > 0) {
          depth += (s[j] == '(' ? 1 : 0) - (s[j] == ')' ? 1 : 0);
          j++;
        }
        if (!s.substring(m.end, j).contains('tooltip')) bad.add('${f.path}:${s.substring(0, m.start).split('\n').length}');
      }
      if (!f.path.endsWith('app_theme.dart') && !f.path.endsWith('common.dart') && RegExp(r'Color\(0xFF(F6F8FC|111827|667085|E4E7EC)\)').hasMatch(s)) {
        bad.add('${f.path}: hard-coded colour, use AppColors');
      }
    }
    expect(bad, isEmpty);
  });

  test('theme choice is stored on the device', () async {
    await ThemeStore.set(ThemeMode.dark);
    ThemeStore.mode.value = ThemeMode.system;
    await ThemeStore.load();
    expect(ThemeStore.mode.value, ThemeMode.dark);
  });

  testWidgets('settings: picking dark mode changes the stored mode', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(onLogout: () async {})));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('settingsTheme')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme_dark')));
    await settle(tester);
    expect(ThemeStore.mode.value, ThemeMode.dark);
  });

  final screens = <String, Widget Function()>{
    'role selection': () => const RoleSelectionScreen(),
    'customer login': () => const CustomerLoginScreen(),
    'driver login': () => const DriverLoginScreen(),
    'settings': () => SettingsScreen(onLogout: () async {}),
    'help': () => const HelpScreen(),
    'terms': () => PolicyScreen.terms,
    'privacy': () => PolicyScreen.privacy,
    'refund': () => PolicyScreen.refund,
    'onboarding': () => const OnboardingScreen(),
    'delete account': () => const AccountDeletionScreen(),
    'notifications': () => NotificationsScreen(onOpenBooking: (_) {}, reminders: Stream.value(const [])),
    'driver home': () => const DriverHomeScreen(),
    'wallet': () => const WalletScreen(),
    'post load': () => const PostLoadScreen(),
    'customer home': () => const CustomerHomeScreen(),
  };

  for (final dark in [false, true]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} fits 360x640 at 2.0x text (${dark ? 'dark' : 'light'})', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        AppPalette.current = dark ? AppPalette.dark : AppPalette.light;
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          debugPrint('LAYOUT ${e.key}: ${d.toString()}');
          prev?.call(d);
        };
        addTearDown(() => FlutterError.onError = prev);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: e.value(),
        ));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
