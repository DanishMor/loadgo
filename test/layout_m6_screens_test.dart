import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_alerts_screen.dart';
import 'package:transport_app/admin/admin_appeals_screen.dart';
import 'package:transport_app/admin/admin_cohorts_screen.dart';
import 'package:transport_app/admin/admin_dispatch_screen.dart';
import 'package:transport_app/admin/admin_invites_screen.dart';
import 'package:transport_app/admin/admin_payment_aging_screen.dart';
import 'package:transport_app/admin/admin_pilot_control_screen.dart';
import 'package:transport_app/admin/admin_pilot_report_screen.dart';
import 'package:transport_app/admin/admin_search_screen.dart';
import 'package:transport_app/admin/admin_surveys_screen.dart';
import 'package:transport_app/core/bilty/lr_register_screen.dart';
import 'package:transport_app/core/call/mic_test.dart';
import 'package:transport_app/core/chat/strike_appeal_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/theme/app_theme.dart';

/// MASTER-6 Task 49: the screens added in MASTER-6 fit a 360 x 640 phone at 2.0x
/// text, light and dark, in all 12 languages' longest case (Kashmiri/Urdu are
/// right to left), with empty data.
void main() {
  final screens = <String, Widget Function()>{
    'invite codes': () => const AdminInvitesScreen(),
    'cohorts': () => const AdminCohortsScreen(),
    'dispatch': () => const AdminDispatchScreen(),
    'pilot report': () => const AdminPilotReportScreen(),
    'alerts': () => const AdminAlertsScreen(),
    'search': () => const AdminSearchScreen(),
    'surveys': () => const AdminSurveysScreen(),
    'payment aging': () => const AdminPaymentAgingScreen(),
    'pilot control': () => const AdminPilotControlScreen(),
    'strike appeals (admin)': () => AdminAppealsScreen(appeals: Stream.value(const [])),
    'strike appeals (person)': () => StrikeAppealScreen(load: () async => []),
    'mic test': () => const MicTestScreen(),
    'LR register': () => LrRegisterScreen(lrs: Stream.value(const []), shares: Stream.value(const [])),
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'admin1');
  });

  for (final lang in [AppLanguage.english, AppLanguage.urdu, AppLanguage.tamil]) {
    for (final dark in [false, true]) {
      for (final e in screens.entries) {
        testWidgets('${e.key} fits 360x640 at 2.0x (${lang.name}, ${dark ? 'dark' : 'light'})', (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          languageNotifier.value = lang;
          addTearDown(() => languageNotifier.value = AppLanguage.english);
          AppPalette.current = dark ? AppPalette.dark : AppPalette.light;
          await tester.pumpWidget(LanguageScope(
            notifier: languageNotifier,
            child: MaterialApp(
              theme: AppTheme.build(Brightness.light),
              darkTheme: AppTheme.build(Brightness.dark),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, child) => Directionality(
                textDirection: lang.textDirection,
                child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
              ),
              home: e.value(),
            ),
          ));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
