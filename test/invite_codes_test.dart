import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_invites_screen.dart';
import 'package:transport_app/auth/invite_gate_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pilot/invite_codes.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/server_clock.dart';

import 'test_utils.dart';

/// MASTER-6 Task 1: pilot invite codes and the whitelist.
void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    ServerClock.reset();
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
  });

  test('codes: normalised, 8 characters from the clear alphabet, always different', () {
    expect(InviteCode.normalise('ab-23 cd'), 'AB23CD');
    final seen = <String>{};
    final r = Random(1);
    for (var i = 0; i < 500; i++) {
      final c = InviteCode.generate(r);
      expect(c.length, InviteCode.codeLength);
      expect(c.split('').every(InviteCode.alphabet.contains), isTrue);
      seen.add(c);
    }
    expect(seen.length, greaterThan(495));
  });

  test('check: role, switch, last day and uses', () {
    final now = DateTime(2026, 10, 9, 12);
    InviteCode c({String role = 'any', int uses = 0, bool active = true, DateTime? exp}) => InviteCode(code: 'ABCD2345', role: role, maxUses: 2, uses: uses, active: active, expiresAt: exp ?? DateTime(2026, 10, 20));
    expect(c().check(forRole: 'driver', now: now), InviteCheck.ok);
    expect(c(role: 'driver').check(forRole: 'driver', now: now), InviteCheck.ok);
    expect(c(role: 'driver').check(forRole: 'customer', now: now), InviteCheck.wrongRole);
    expect(c(active: false).check(forRole: 'driver', now: now), InviteCheck.off);
    expect(c(exp: DateTime(2026, 10, 9, 12)).check(forRole: 'driver', now: now), InviteCheck.expired);
    expect(c(uses: 2).check(forRole: 'driver', now: now), InviteCheck.usedUp);
    expect(c(uses: 1).left, 1);
  });

  test('redeem: counts one use and records the person; a used-up or unknown code is refused', () async {
    await db.collection('invite_codes').doc('ABCD2345').set({'role': 'customer', 'maxUses': 1, 'uses': 0, 'active': true, 'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 2)))});
    expect(await InviteService.redeem('abcd-2345', role: 'driver'), InviteCheck.wrongRole);
    expect(await InviteService.redeem('ZZZZ', role: 'customer'), InviteCheck.unknown);
    expect(await InviteService.redeem('ABCD2345', role: 'customer'), InviteCheck.ok);
    expect((await db.collection('invite_codes').doc('ABCD2345').get()).data()!['uses'], 1);
    expect((await db.collection('invite_redemptions').doc('u1').get()).data()!['code'], 'ABCD2345');
    expect(await InviteService.redeem('ABCD2345', role: 'customer'), InviteCheck.usedUp);
  });

  test('mayJoin: open when the pilot switch is off; otherwise a code or the whitelist', () async {
    expect(await InviteService.mayJoin(uid: 'u1', phone: '+919999900001'), isTrue);
    await db.collection('config').doc('pilot').set({'inviteOnly': true});
    expect(await InviteService.mayJoin(uid: 'u1', phone: '+919999900001'), isFalse);
    await db.collection('pilot_whitelist').doc('919999900001').set({'createdBy': 'a'});
    expect(await InviteService.mayJoin(uid: 'u1', phone: '+91 99999 00001'), isTrue);
    await db.collection('invite_redemptions').doc('u2').set({'code': 'ABCD2345'});
    expect(await InviteService.mayJoin(uid: 'u2', phone: null), isTrue);
    expect(await InviteService.mayJoin(uid: 'u3', phone: null), isFalse);
  });

  test('admin: create writes the code and an audit event; switch off is audited', () async {
    final code = await InviteService.create(role: 'driver', route: 'Delhi-Jaipur', maxUses: 5, days: 7);
    final d = (await db.collection('invite_codes').doc(code).get()).data()!;
    expect(d['role'], 'driver');
    expect(d['uses'], 0);
    expect(d['createdBy'], 'u1');
    await InviteService.setActive(code, false);
    final list = await InviteService.list();
    expect(list.single.active, isFalse);
    final audit = await db.collection('audit_events').get();
    expect(audit.docs.map((e) => e.data()['data']['action']), containsAll(['invite_create', 'invite_active']));
  });

  testWidgets('gate screen: wrong code shows the reason, right code opens the next screen', (tester) async {
    await db.collection('invite_codes').doc('ABCD2345').set({'role': 'any', 'maxUses': 3, 'uses': 0, 'active': true, 'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 2)))});
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: InviteGateScreen(role: 'customer', next: () => const Scaffold(body: Text('PROFILE'))))));
    await settle(tester);
    expect(find.byKey(const ValueKey('inviteBody')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('inviteCode')), 'NOPE1234');
    await tester.tap(find.byKey(const ValueKey('inviteGo')));
    await settle(tester);
    expect(find.text('This code was not found. Check it and try again.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('inviteCode')), 'abcd2345');
    await tester.tap(find.byKey(const ValueKey('inviteGo')));
    await settle(tester);
    expect(find.text('PROFILE'), findsOneWidget);
  });

  testWidgets('admin screen lists codes with uses left and a switch', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: AdminInvitesScreen(load: () async => [const InviteCode(code: 'ABCD2345', role: 'driver', route: 'Delhi', maxUses: 5, uses: 2)]))));
    await settle(tester);
    expect(find.text('ABCD2345'), findsOneWidget);
    expect(find.textContaining('3 of 5 uses left'), findsOneWidget);
    expect(find.byKey(const ValueKey('invToggle_ABCD2345')), findsOneWidget);
  });
}
