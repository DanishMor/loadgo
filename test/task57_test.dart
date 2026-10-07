import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_demo_screen.dart';
import 'package:transport_app/admin/admin_feedback_screen.dart';
import 'package:transport_app/admin/admin_assistant_screen.dart';
import 'package:transport_app/admin/admin_health_screen.dart';
import 'package:transport_app/admin/admin_lists.dart';
import 'package:transport_app/admin/admin_rating_burst_screen.dart';
import 'package:transport_app/admin/admin_templates_screen.dart';
import 'package:transport_app/core/assistant/sahayak_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/strings.dart';
import 'package:transport_app/core/search/global_search_screen.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/settings/feedback_screen.dart';
import 'package:transport_app/core/settings/legal_screens.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/trip/trip_history_screen.dart';
import 'package:transport_app/customer/spending_screen.dart';
import 'package:transport_app/driver/simple_home_screen.dart';

import 'test_utils.dart';

void main() {
  setUp(() async {
    final db = FakeFirebaseFirestore();
    await db.collection('admins').doc('u1').set({'createdBy': 'console'});
    await db.collection('users').doc('u1').set({'role': 'driver', 'name': 'Asha'});
    await db.collection('users').doc('u2').set({'name': 'Bala', 'phone': '+919222222222', 'riskTier': 'restricted', 'role': 'customer'});
    await db.collection('app_errors').add({
      'message': 'Null check operator used on a null value in a rather long error text that must wrap and not overflow the card',
      'screen': 'driver/driver_trip_screen.dart', 'kind': 'flutter', 'appVersion': '1.0.0+1', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 5)),
    });
    Backend.useFakes(db: db, uid: () => 'u1', auth: () => MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1', phoneNumber: '+919999999999')));
    SharedPreferences.setMockInitialValues({});
    AppPalette.current = AppPalette.light;
  });

  group('string tables', () {
    test('a key lives in one table only (a later table would silently replace an earlier one)', () {
      final seen = <String, int>{};
      final dup = <String>[];
      for (var i = 0; i < stringTables.length; i++) {
        for (final k in stringTables[i].keys) {
          if (seen.containsKey(k)) dup.add('$k (tables ${seen[k]} and $i)');
          seen[k] = i;
        }
      }
      expect(dup, isEmpty);
    });

    test('every extra table entry has exactly 12 non-empty texts with the same placeholders', () {
      final ph = RegExp(r'\{(\w+)\}');
      final bad = <String>[];
      for (final table in stringTables) {
        for (final e in table.entries) {
          if (e.value.length != 12 || e.value.any((s) => s.trim().isEmpty)) {
            bad.add(e.key);
            continue;
          }
          final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
          for (var i = 1; i < 12; i++) {
            if (ph.allMatches(e.value[i]).map((m) => m[1]).toSet().difference(want).isNotEmpty || want.difference(ph.allMatches(e.value[i]).map((m) => m[1]).toSet()).isNotEmpty) bad.add('${e.key}/$i');
          }
        }
      }
      expect(bad, isEmpty);
    });
  });

  group('large lists use builders', () {
    test('lists of unbounded admin and chat data are not built with ListView(children: [for ...])', () {
      for (final f in [
        'lib/admin/admin_payouts_screen.dart',
        'lib/admin/admin_fraud_cases_screen.dart',
        'lib/admin/admin_lists.dart',
        'lib/core/network/network_chat_screen.dart',
      ]) {
        final s = File(f).readAsStringSync();
        expect(RegExp(r'ListView\(\s*(reverse: true, )?(padding: [^\n]*?, )?children: \[\s*for \(final').hasMatch(s), isFalse, reason: f);
        expect(s, contains('ListView.builder'), reason: f);
      }
    });
  });

  // The screens added in Tasks 41-56, at 360x640 with 1.3x text, light and dark.
  final screens = <String, Widget Function()>{
    'admin health': () => const AdminHealthScreen(),
    'admin templates': () => const AdminTemplatesScreen(),
    'admin demo': () => const AdminDemoScreen(),
    'admin rating bursts': () => const AdminRatingBurstScreen(),
    'admin feedback': () => const AdminFeedbackScreen(),
    'admin assistant log': () => const AdminAssistantScreen(),
    'admin users (bulk actions)': () => const AdminUsersScreen(),
    'feedback form': () => const FeedbackScreen(),
    'search (customer)': () => const GlobalSearchScreen(isDriver: false, bookings: Stream.empty(), loads: Stream.empty(), tickets: Stream.empty(), places: Stream.empty()),
    'search (driver)': () => const GlobalSearchScreen(isDriver: true, bookings: Stream.empty(), loads: Stream.empty(), tickets: Stream.empty(), places: Stream.empty()),
    'sahayak': () => const SahayakScreen(role: 'customer', logUnknown: false),
    'trip history': () => TripHistoryScreen(bookings: () => Stream.value(const []), onOpen: (_) {}),
    'spending': () => SpendingScreen(bookings: () => Stream.value(const [])),
    'simple driver home': () => const SimpleDriverHome(),
    'simple money': () => const SimpleMoneyScreen(),
    'privacy (public link)': () => PolicyScreen.privacy,
  };

  for (final dark in [false, true]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} fits 360x640 at 1.3x text (${dark ? 'dark' : 'light'})', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        AppPalette.current = dark ? AppPalette.dark : AppPalette.light;
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
          home: LanguageScope(notifier: languageNotifier, child: e.value()),
        ));
        await settle(tester);
        expect(tester.takeException(), isNull);
        // Nothing may be painted in the old light colours on a dark page.
        if (dark) expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
      });
    }
  }
}
