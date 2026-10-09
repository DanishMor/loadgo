import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_alerts_screen.dart';
import 'package:transport_app/core/admin/admin_alerts.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-6 Task 14: the alerts center.
void main() {
  final now = DateTime(2026, 10, 9, 15);

  test('busiest day: counts only the next 14 days, picks the biggest day, earliest on a tie', () {
    final r = AdminAlerts.busiestExpiryDay([
      DateTime(2026, 10, 8), // yesterday: out
      DateTime(2026, 10, 12, 9), DateTime(2026, 10, 12, 18), DateTime(2026, 10, 12),
      DateTime(2026, 10, 14), DateTime(2026, 10, 14),
      DateTime(2026, 10, 23, 23), // last day of the window: in
      DateTime(2026, 10, 24), // day 15: out
    ], now)!;
    expect((r.day, r.count, r.total), (DateTime(2026, 10, 12), 3, 6));
    expect(AdminAlerts.busiestExpiryDay([DateTime(2027)], now), isNull);
    final tie = AdminAlerts.busiestExpiryDay([DateTime(2026, 10, 20), DateTime(2026, 10, 20), DateTime(2026, 10, 11), DateTime(2026, 10, 11)], now)!;
    expect(tie.day, DateTime(2026, 10, 11));
  });

  test('build: zero counts are left out, critical first, and a cluster of papers is a warning', () {
    final list = AdminAlerts.build(
      role: StaffRole.superAdmin,
      openSos: 2,
      openFraudCases: 0,
      unreviewedSignals: 4,
      strikeUsers: 1,
      heldUsers: 3,
      pendingDeletions: 1,
      docs: (day: DateTime(2026, 10, 12), count: 5, total: 9),
    );
    expect(list.map((a) => a.id), ['sos', 'signals', 'strikes', 'docs', 'held', 'deletions']);
    expect(list.firstWhere((a) => a.id == 'docs').level, AlertLevel.warning);
    final small = AdminAlerts.build(role: StaffRole.superAdmin, docs: (day: DateTime(2026, 10, 12), count: 2, total: 2));
    expect(small.single.level, AlertLevel.info);
    expect(AdminAlerts.build(role: StaffRole.superAdmin), isEmpty);
  });

  test('build: each role sees only what it can work on', () {
    List<String> ids(String role) => AdminAlerts.build(role: role, openSos: 1, openFraudCases: 1, unreviewedSignals: 1, strikeUsers: 1, heldUsers: 1, pendingDeletions: 1, docs: (day: now, count: 1, total: 1)).map((a) => a.id).toList();
    expect(ids(StaffRole.finance), isEmpty);
    expect(ids(StaffRole.support), containsAll(['sos', 'strikes', 'deletions']));
    expect(ids(StaffRole.support), isNot(contains('fraud')));
    expect(ids(StaffRole.verifier), containsAll(['signals', 'docs']));
    expect(ids(StaffRole.verifier), isNot(contains('sos')));
    expect(ids(StaffRole.ops), containsAll(['sos', 'fraud', 'signals', 'held']));
  });

  test('the service counts from the database for a role', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'a1');
    final soon = Timestamp.fromDate(DateTime.now().add(const Duration(days: 3)));
    await db.collection('sos_alerts').doc('s1').set({'status': 'open'});
    await db.collection('sos_alerts').doc('s2').set({'status': 'resolved'});
    await db.collection('fraud_cases').doc('f1').set({'status': 'investigating'});
    await db.collection('fraud_cases').doc('f2').set({'status': 'resolved'});
    await db.collection('users').doc('u1').set({'chatStrikes': 4, 'riskTier': 'restricted'});
    await db.collection('users').doc('u2').set({'chatStrikes': 1, 'riskTier': 'normal'});
    await db.collection('risk_signals').doc('r1').set({'createdAt': Timestamp.now(), 'type': 'new_device'});
    await db.collection('risk_signals').doc('r2').set({'createdAt': Timestamp.now(), 'reviewed': true});
    await db.collection('vehicles').doc('v1').set({'ownerId': 'o', 'number': 'MH12AB1234', 'type': 'Mini', 'capacity': 3, 'status': 'active', 'availability': 'available', 'rcNumber': 'x', 'docs': {'insurance': {'number': 'I', 'expiry': soon}, 'permit': {'number': 'P', 'expiry': soon}}});
    final list = await AdminConsoleService.alerts(role: StaffRole.superAdmin);
    final byId = {for (final a in list) a.id: a};
    expect(byId['sos']!.count, 1);
    expect(byId['fraud']!.count, 1);
    expect(byId['strikes']!.count, 1);
    expect(byId['held']!.count, 1);
    expect(byId['signals']!.count, 1);
    expect(byId['docs']!.count, 2);
    expect(list.first.level, AlertLevel.critical);
  });

  testWidgets('the screen lists the alerts in words and says when all is clear', (tester) async {
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: AdminAlertsScreen(load: () async => [
            const AdminAlert(id: 'sos', level: AlertLevel.critical, count: 2, area: 'adminSos'),
            AdminAlert(id: 'docs', level: AlertLevel.warning, count: 9, area: 'adminVehicles', peakDay: DateTime(2026, 10, 12), peakCount: 5),
          ])),
    ));
    await settle(tester);
    expect(find.text('2 open SOS alerts'), findsOneWidget);
    expect(find.textContaining('9 vehicle papers run out'), findsOneWidget);
    expect(find.textContaining('most on 12/10 (5)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: AdminAlertsScreen(load: () async => const []))));
    await settle(tester);
    expect(find.textContaining('All clear'), findsOneWidget);
  });
}
