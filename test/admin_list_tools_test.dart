import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_lists.dart';
import 'package:transport_app/core/admin/admin_export.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-5 Task 38: every admin list searches, pages, saves filters and exports.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    for (var i = 0; i < 120; i++) {
      await db.collection('reports').doc('r$i').set({
        'reason': i.isEven ? 'rude driver' : 'late delivery',
        'status': 'open',
        'reporterId': 'u$i',
        'description': 'private free text $i',
        'phone': '+919800000000',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1).add(Duration(minutes: i))),
      });
    }
  });

  test('the CSV has id and plain fields only: no phone, e-mail, KYC or free text', () {
    final csv = AdminExport.genericCsv([
      ('x1', {'status': 'open', 'phone': '+919800000000', 'email': 'a@b.c', 'description': 'long text', 'dlNumber': 'MH1', 'kyc': 'x', 'amount': 5, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)), 'nested': {'a': 1}, 'deadline': 'soon'}),
      ('x2', {'status': 'closed', 'amount': 7}),
    ]);
    final lines = csv.trim().split('\n');
    expect(lines.first, 'id,amount,createdAt,deadline,status');
    expect(lines[1], 'x1,5,2026-10-02,soon,open');
    expect(lines[2], 'x2,7,,,closed');
    for (final secret in ['9800', 'a@b.c', 'long text', 'MH1']) {
      expect(csv, isNot(contains(secret)));
    }
  });

  testWidgets('50 rows at first, Show 50 more adds the next, search narrows, a filter can be saved and reused', (tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: AdminReportsScreen())));
    await settle(tester);
    Future<void> toFooter() => tester.scrollUntilVisible(find.byKey(const ValueKey('adminExportCsv')), 800, scrollable: find.byType(Scrollable).last);
    await toFooter();
    expect(find.text('Showing 50 of 100'), findsOneWidget); // the list is read 100 at a time
    await tester.tap(find.byKey(const ValueKey('adminShowMore')));
    await settle(tester);
    await toFooter();
    expect(find.text('Showing 100 of 100'), findsOneWidget);
    expect(find.byKey(const ValueKey('adminShowMore')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('adminListSearch')), 'rude');
    await settle(tester);
    await toFooter();
    expect(find.text('Showing 50 of 50'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('adminSavedFilters')));
    await settle(tester);
    await tester.tap(find.text('Save this search'));
    await settle(tester);
    expect((await SharedPreferences.getInstance()).getStringList('adminfilters_adminReports'), ['rude']);

    await tester.enterText(find.byKey(const ValueKey('adminListSearch')), '');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('adminSavedFilters')));
    await settle(tester);
    await tester.tap(find.text('rude').last);
    await settle(tester);
    await toFooter();
    expect(find.text('Showing 50 of 50'), findsOneWidget);
  });
}
