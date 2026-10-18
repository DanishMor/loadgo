import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_dashboard_screen.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';

import 'test_utils.dart';

/// U36: the admin home in five groups with the component kit.
void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    FeaturesService.reset();
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'a1');
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  test('every screen key has a group, and the groups are the five known ones', () {
    for (final k in ['adminUsers', 'adminLoads', 'adminSos', 'adminFinance', 'adminConfig', 'somethingNew']) {
      expect(adminGroups, contains(adminGroupOf(k)));
    }
    expect(adminGroupOf('adminUsers'), 'adGroupPeople');
    expect(adminGroupOf('adminDispatchMonitor'), 'adGroupOps');
    expect(adminGroupOf('adminSos'), 'adGroupSafety');
    expect(adminGroupOf('adminPayouts'), 'adGroupMoney');
    expect(adminGroupOf('somethingNew'), 'adGroupTools');
  });

  Future<void> show(WidgetTester t, {Brightness b = Brightness.light, double scale = 1}) async {
    t.view.physicalSize = const Size(360 * 2, 3000 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        theme: AppTheme.build(b),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: const AdminDashboardScreen(),
      ),
    ));
    await settle(t);
  }

  testWidgets('the five group titles show, and the dispatch monitor sits under Loads, trips and dispatch', (t) async {
    await show(t);
    for (final g in adminGroups) {
      expect(find.byKey(ValueKey('adminGroup_$g')), findsOneWidget, reason: g);
    }
    expect(find.byKey(const ValueKey('admin_adminDispatchMonitor')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_adminConfig')), findsOneWidget);
  });

  testWidgets('a verifier sees only the groups that hold something they can act on', (t) async {
    await t.runAsync(() => db.collection('admins').doc('a1').set({'role': 'verifier'}));
    await show(t);
    expect(find.byKey(const ValueKey('admin_adminTickets')), findsNothing);
    expect(find.byKey(const ValueKey('admin_driverVerification')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_adminConfig')), findsNothing);
    expect(find.text('Verifier'), findsOneWidget);
    expect(find.byKey(const ValueKey('adminGroup_adGroupMoney')), findsNothing, reason: 'no money screen is open to a verifier');
  });

  testWidgets('dark, 2.0x text and Hindi: no overflow', (t) async {
    languageNotifier.value = AppLanguage.hindi;
    await show(t, b: Brightness.dark, scale: 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('uiV2 off: the old flat list', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.uiV2: false});
    await show(t);
    expect(find.byKey(const ValueKey('adminGroup_adGroupPeople')), findsNothing);
    expect(find.byKey(const ValueKey('admin_adminUsers')), findsOneWidget);
  });
}
