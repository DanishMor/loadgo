import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_lists.dart';
import 'package:transport_app/admin/admin_user_screen.dart';
import 'package:transport_app/auth/banned_screen.dart';
import 'package:transport_app/auth/start_resolvers.dart';
import 'package:transport_app/core/models/risk.dart';
import 'package:transport_app/core/services/admin_user_service.dart';
import 'package:transport_app/core/services/audit_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/risk_service.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() async {
    db = FakeFirebaseFirestore();
    uid = 'admin1';
    Backend.useFakes(db: db, uid: () => uid);
    await db.collection('users').doc('d1').set({'driverName': 'Ramesh', 'phone': '+919811111111', 'roles': ['driver'], 'verified': true, 'verificationStatus': 'approved'});
    await db.collection('users').doc('c1').set({'name': 'Anita', 'phone': '+919822222222'});
  });

  Future<List<Map<String, dynamic>>> audit(String target) async =>
      (await db.collection('audit_events').where('targetId', isEqualTo: target).get()).docs.map((d) => d.data()).toList();

  test('suspend, ban and restore change the tier, keep the reason and write an audit event each', () async {
    await AdminUserService.setStanding('c1', UserAction.suspend, reason: 'abuse in chat');
    var u = (await db.collection('users').doc('c1').get()).data()!;
    expect((u['riskTier'], u['riskReason']), ('suspended', 'abuse in chat'));
    expect(RiskTier.canTransact(u['riskTier'] as String), isFalse);
    await AdminUserService.setStanding('c1', UserAction.ban, reason: 'repeat fraud');
    expect((await db.collection('users').doc('c1').get())['riskTier'], 'banned');
    await AdminUserService.setStanding('c1', UserAction.unban);
    u = (await db.collection('users').doc('c1').get()).data()!;
    expect((u['riskTier'], u['riskReason']), ('normal', ''));
    final events = await audit('c1');
    expect(events.map((e) => (e['type'], (e['data'] as Map)['action'])).toList(), [('user_action', 'suspend'), ('user_action', 'ban'), ('user_action', 'unban')]);
    expect(events.every((e) => e['actorId'] == 'admin1'), isTrue);
    expect((events[1]['data'] as Map)['from'], 'suspended');
  });

  test('a suspend or ban needs a reason; no self-action; nothing to change is refused', () async {
    await expectLater(AdminUserService.setStanding('c1', UserAction.ban, reason: ' x '), throwsA(isA<UserActionException>().having((e) => e.reason, 'r', 'reason')));
    await expectLater(AdminUserService.setStanding('admin1', UserAction.suspend, reason: 'testing'), throwsA(isA<UserActionException>().having((e) => e.reason, 'r', 'self')));
    await expectLater(AdminUserService.setStanding('c1', UserAction.unban), throwsA(isA<UserActionException>().having((e) => e.reason, 'r', 'state')));
    expect(() => AdminUserService.setStanding('c1', 'delete'), throwsArgumentError);
    expect(await audit('c1'), isEmpty, reason: 'refused actions leave no trace');
  });

  test('force re-verify sends the driver back to pending with the admin recorded', () async {
    await expectLater(AdminUserService.forceReverify('d1', reason: ''), throwsA(isA<UserActionException>()));
    await AdminUserService.forceReverify('d1', reason: 'licence photo looks old');
    final u = (await db.collection('users').doc('d1').get()).data()!;
    expect((u['verified'], u['verificationStatus']), (false, 'pending'));
    expect((u['verificationMeta'] as Map)['by'], 'admin1');
    expect(((await audit('d1')).single['data'] as Map)['action'], 'reverify');
  });

  test('notes are private to admins, newest first, and audited without the text', () async {
    await AdminUserService.addNote('d1', ' called him, he will renew ');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AdminUserService.addNote('d1', 'renewed');
    final notes = await AdminUserService.watchNotes('d1').first;
    expect(notes.map((n) => n.text), ['renewed', 'called him, he will renew']);
    await expectLater(AdminUserService.addNote('d1', '   '), throwsA(isA<UserActionException>()));
    final e = await audit('d1');
    expect(e.length, 2);
    expect(e.every((x) => !(x['data'] as Map).containsKey('text')), isTrue);
    final history = await AdminUserService.watchHistory('d1').first;
    expect(history.map((h) => h.action), everyElement('note'));
  });

  test('flagged list includes banned users; AuditType knows user_action', () async {
    await AdminUserService.setStanding('c1', UserAction.ban, reason: 'fraud ring');
    expect((await RiskService.flagged()).single.riskTier, 'banned');
    expect(AuditType.all, contains('user_action'));
  });

  test('a banned account is stopped at start', () async {
    uid = 'c1';
    await db.collection('users').doc('c1').update({'riskTier': 'banned', 'profileComplete': true});
    expect(await resolveDriverStart(), isA<BannedScreen>());
  });

  testWidgets('screen: ban with a reason, restore, add a note, see the history', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AdminUserScreen(uid: 'd1')));
    await settle(tester);
    expect(find.text('Account status: Normal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('actBan')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('actionReason')), 'x');
    await tester.tap(find.byKey(const ValueKey('actionConfirm')));
    await settle(tester);
    expect(find.text('Write a reason of at least 3 characters'), findsOneWidget);
    expect((await db.collection('users').doc('d1').get()).data()!.containsKey('riskTier'), isFalse);
    await tester.tap(find.byKey(const ValueKey('actBan')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('actionReason')), 'fake documents');
    await tester.tap(find.byKey(const ValueKey('actionConfirm')));
    await settle(tester);
    expect(find.text('Account status: Banned'), findsOneWidget);
    expect(find.byKey(const ValueKey('actBan')), findsNothing);
    expect(find.byKey(const ValueKey('hist_ban')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('actUnban')));
    await settle(tester);
    expect(find.text('Account status: Normal'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('noteField')), 'owner called, sorted');
    await tester.tap(find.byKey(const ValueKey('noteAdd')));
    await settle(tester);
    expect(find.text('owner called, sorted'), findsOneWidget);
    expect(find.byKey(const ValueKey('hist_unban')), findsOneWidget);
  });

  testWidgets('the users list opens the user screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminUsersScreen()));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('user_c1')));
    await settle(tester);
    expect(find.text('Anita'), findsWidgets);
    expect(find.byKey(const ValueKey('actSuspend')), findsOneWidget);
  });
}
