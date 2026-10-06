import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/enterprise/business_roles.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/business_ops.dart';
import 'package:transport_app/core/models/support_ticket.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/business_ops_service.dart';
import 'package:transport_app/core/services/business_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/support_service.dart';
import 'package:transport_app/customer/business_hub_screen.dart';
import 'package:transport_app/customer/business_ops_screens.dart';
import 'package:transport_app/customer/business_team_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth current;
  final people = <String, MockFirebaseAuth>{};
  void signIn(String uid, [String? phone]) =>
      current = people.putIfAbsent(uid, () => MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid, phoneNumber: phone ?? '+9198000000${uid.hashCode.abs() % 100}')));

  setUp(() async {
    db = FakeFirebaseFirestore();
    people.clear();
    signIn('o1', '+919800000001');
    Backend.useFakes(db: db, uid: () => current.currentUser?.uid, auth: () => current);
    languageNotifier.value = AppLanguage.english;
    await db.collection('users').doc('o1').set({'role': 'customer', 'name': 'Owner', 'phone': '+919800000001', 'business': {'legalName': 'Acme Ltd'}});
  });

  /// Adds an active member with [role] to company o1.
  Future<void> member(String uid, String role, String phone) async {
    await db.collection('users').doc(uid).set({'role': 'customer', 'name': uid});
    await db.collection('business_members').doc('o1_$uid').set({'ownerId': 'o1', 'ownerName': 'Acme Ltd', 'memberId': uid, 'memberName': uid, 'memberPhone': phone, 'role': role, 'active': true});
  }

  Future<String> post({num? budget = 50000, String? businessId = 'o1'}) => LoadService.post(
      pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: budget, pickupDate: DateTime(2026, 10, 9), notes: '', businessId: businessId);

  group('role table (A4, BIZ4, BIZ5)', () {
    test('who can do what', () {
      expect(bizRolesWith(BizPerm.postLoads), ['owner', 'manager', 'dispatch', 'booker']);
      expect(bizRolesWith(BizPerm.viewBookings), BizRole.all);
      expect(bizRolesWith(BizPerm.approveLoads), ['owner', 'manager']);
      expect(bizRolesWith(BizPerm.manageTeam), ['owner']);
      expect(bizRolesWith(BizPerm.viewStatements), ['owner', 'manager', 'accounts', 'viewer']);
      expect(bizRolesWith(BizPerm.manageExpenses), ['owner', 'manager', 'accounts']);
      expect(bizRolesWith(BizPerm.managePool), ['owner', 'manager', 'dispatch']);
      expect(bizRolesWith(BizPerm.manageContracts), ['owner', 'manager']);
      expect(bizRolesWith(BizPerm.businessSupport), ['owner', 'manager', 'accounts']);
      expect(bizCan('viewer', BizPerm.postLoads), isFalse);
      expect(bizCan(null, BizPerm.viewBookings), isFalse);
      expect(bizCan('stranger', BizPerm.viewBookings), isFalse);
    });

    test('the role lists in firestore.rules say the same', () {
      // The rules text is the contract (DOC10): every bizActs(...) list must be a role set from the table.
      final rules = File('firestore.rules').readAsStringSync();
      for (final (perm, list) in [
        (BizPerm.manageContracts, "['manager']"),
        (BizPerm.managePool, "['manager', 'dispatch']"),
        (BizPerm.manageExpenses, "['manager', 'accounts']"),
        (BizPerm.businessSupport, "['manager', 'accounts']"),
        (BizPerm.viewStatements, "['manager', 'accounts', 'viewer']"),
        (BizPerm.postLoads, "['booker', 'manager', 'dispatch']"),
        (BizPerm.approveLoads, "['manager']"),
      ]) {
        expect(rules, contains(list), reason: perm);
        final fromTable = bizRolesWith(perm).where((r) => r != BizRole.owner).toSet();
        final fromRules = RegExp(r"'(\w+)'").allMatches(list).map((m) => m.group(1)!).toSet();
        expect(fromRules, fromTable, reason: perm);
      }
    });
  });

  group('roles on invites and members', () {
    test('invite with a role, the member joins with it, the owner changes it, postingBusinessId follows the role', () async {
      await db.collection('users').doc('m1').set({'role': 'customer', 'name': 'Mina'});
      await expectLater(() => BusinessService.invite('9876543210', role: 'ceo'), throwsArgumentError);
      final id = await BusinessService.invite('9876543210', role: BizRole.viewer);
      expect((await db.collection('business_invites').doc(id).get()).data()!['role'], 'viewer');
      signIn('m1', '+919876543210');
      final invite = (await BusinessService.watchMyInvites().first).single;
      expect(invite.role, 'viewer');
      await BusinessService.respond(invite, accept: true);
      var ctx = (await BusinessService.myContext())!;
      expect((ctx.ownerId, ctx.role), ('o1', 'viewer'));
      expect(ctx.can(BizPerm.viewStatements), isTrue);
      expect(await BusinessService.postingBusinessId(), isNull, reason: 'a viewer does not post');
      signIn('o1');
      final m = (await BusinessService.watchMembers().first).single;
      await expectLater(() => BusinessService.setRole(m, 'owner'), throwsArgumentError);
      await BusinessService.setRole(m, BizRole.dispatch);
      signIn('m1');
      ctx = (await BusinessService.myContext())!;
      expect(ctx.role, 'dispatch');
      expect(await BusinessService.postingBusinessId(), 'o1');
    });

    test('the owner is the owner; a stranger has no company', () async {
      expect((await BusinessService.myContext())!.isOwner, isTrue);
      signIn('x1');
      await db.collection('users').doc('x1').set({'role': 'customer'});
      expect(await BusinessService.myContext(), isNull);
    });
  });

  group('approval workflow (BIZ6)', () {
    test('no limit, owner and managers post freely; a booker over the limit waits; under the limit does not', () async {
      await member('b1', BizRole.booker, '+919800000011');
      await member('mg', BizRole.manager, '+919800000012');
      signIn('b1');
      expect(await BusinessOpsService.approvalNeeded('o1', 9999999), isFalse, reason: 'no limit yet');
      signIn('o1');
      await expectLater(() => BusinessOpsService.setApprovalLimit(-1), throwsArgumentError);
      await BusinessOpsService.setApprovalLimit(2000000);
      expect(await BusinessOpsService.approvalLimit('o1'), 2000000);
      expect(await BusinessOpsService.approvalNeeded('o1', 9000000), isFalse, reason: 'owner');
      signIn('mg');
      expect(await BusinessOpsService.approvalNeeded('o1', 9000000), isFalse, reason: 'manager');
      signIn('b1');
      expect(await BusinessOpsService.approvalNeeded('o1', 2000000), isFalse, reason: 'at the limit');
      expect(await BusinessOpsService.approvalNeeded('o1', 2000001), isTrue);
    });

    test('a load over the limit is posted awaiting approval, hidden from drivers, and approve / reject work', () async {
      await member('b1', BizRole.booker, '+919800000011');
      await member('mg', BizRole.manager, '+919800000012');
      signIn('o1');
      await BusinessOpsService.setApprovalLimit(2000000);
      signIn('b1');
      final big = await post(budget: 50000);
      final small = await post(budget: 10000);
      var l = (await db.collection('loads').doc(big).get()).data()!;
      expect(l['status'], LoadStatus.awaitingApproval);
      expect((await db.collection('loads').doc(small).get()).data()!['status'], LoadStatus.open);
      final open = await db.collection('loads').where('status', isEqualTo: LoadStatus.open).get();
      expect(open.docs.map((d) => d.id), [small], reason: 'drivers list open loads only');

      signIn('mg');
      final waiting = await BusinessOpsService.watchAwaitingApproval('o1').first;
      expect(waiting.map((x) => x.id), [big]);
      await BusinessOpsService.decide(waiting.single, approve: true);
      l = (await db.collection('loads').doc(big).get()).data()!;
      expect(l['status'], LoadStatus.open);
      expect((l['approval'] as Map)['by'], 'mg');
      expect((l['approval'] as Map)['decision'], 'approved');

      signIn('b1');
      final second = await post(budget: 90000);
      signIn('o1');
      await BusinessOpsService.decide((await BusinessOpsService.watchAwaitingApproval('o1').first).single, approve: false);
      l = (await db.collection('loads').doc(second).get()).data()!;
      expect((l['status'], l['cancelled']), (LoadStatus.closed, true));
    });

    testWidgets('approvals screen: owner sets the limit, approves a waiting load', (tester) async {
      await tester.runAsync(() async {
        await member('b1', BizRole.booker, '+919800000011');
        await BusinessOpsService.setApprovalLimit(100);
        signIn('b1');
        await post(budget: 50000);
        signIn('o1');
      });
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: ApprovalsScreen(context: BizContext('o1', BizRole.owner)))));
      await settle(tester);
      expect(find.byKey(const ValueKey('approvalLimit')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('approvalLimit')), '25000');
      await tester.tap(find.byKey(const ValueKey('approvalLimitSave')));
      await settle(tester);
      expect(await tester.runAsync(() => BusinessOpsService.approvalLimit('o1')), 2500000);
      final id = (await tester.runAsync(() => db.collection('loads').get()))!.docs.single.id;
      await tester.tap(find.byKey(ValueKey('approve_$id')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('loads').doc(id).get()))!.data()!['status'], LoadStatus.open);
    });
  });

  group('contract vehicles (BIZ8)', () {
    test('add validates, lists by number, expires, deletes', () async {
      await BusinessOpsService.addContract('o1', vehicleNumber: 'mh 12 ab 1234', vehicleType: '20ft', vendorName: 'Ram Transport', ratePerTripPaise: 1800000, validUntil: DateTime(2026, 12, 31), note: 'Pune-Delhi');
      await expectLater(() => BusinessOpsService.addContract('o1', vehicleNumber: 'X', vehicleType: '', vendorName: 'Ram'), throwsA(isA<BusinessOpsException>()));
      await expectLater(() => BusinessOpsService.addContract('o1', vehicleNumber: 'MH12AB9999', vehicleType: '', vendorName: 'R'), throwsA(isA<BusinessOpsException>()));
      await BusinessOpsService.addContract('o1', vehicleNumber: 'GJ01CD5678', vehicleType: '14ft', vendorName: 'Shah Carriers', validUntil: DateTime(2026, 1, 1));
      final list = await BusinessOpsService.watchContracts('o1').first;
      expect(list.map((v) => v.vehicleNumber), ['GJ01CD5678', 'MH12AB1234']);
      expect(list.first.expired(DateTime(2026, 10, 6)), isTrue);
      expect(list.last.expired(DateTime(2026, 10, 6)), isFalse);
      expect(list.last.ratePerTripPaise, 1800000);
      await BusinessOpsService.deleteContract(list.first.id);
      expect((await BusinessOpsService.watchContracts('o1').first).length, 1);
    });
  });

  group('approved driver pool (BIZ9)', () {
    test('add, list, remove; a load limited to the pool carries invite visibility', () async {
      await BusinessOpsService.addToPool('o1', driverId: 'd1', name: 'Ramesh', vehicleNumber: 'MH12AB1234');
      await BusinessOpsService.addToPool('o1', driverId: 'd2', name: 'Suresh');
      await expectLater(() => BusinessOpsService.addToPool('o1', driverId: '', name: 'x'), throwsA(isA<BusinessOpsException>()));
      expect((await BusinessOpsService.watchPool('o1').first).map((p) => p.name), ['Ramesh', 'Suresh']);
      expect(await BusinessOpsService.poolIds('o1'), unorderedEquals(['d1', 'd2']));
      final ids = await BusinessOpsService.poolIds('o1');
      final id = await LoadService.post(
          pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: 1000, pickupDate: DateTime(2026, 10, 9), notes: '',
          businessId: 'o1', visibility: 'invite', allowedDriverIds: ids);
      expect(((await db.collection('loads').doc(id).get()).data()!['allowedDriverIds'] as List).toSet(), {'d1', 'd2'});
      await BusinessOpsService.removeFromPool('o1', 'd1');
      expect(await BusinessOpsService.poolIds('o1'), ['d2']);
    });
  });

  group('spend dashboard (BIZ10)', () {
    final now = DateTime(2026, 10, 6);
    Booking trip(String id, DateTime at, int paise, {String status = 'delivered'}) => Booking(
        id: id, loadId: id, driverId: 'd', vehicleId: 'v', customerId: 'c', status: status, pickup: 'Pune', drop: 'Delhi', cargoType: 'x', weight: 1, vehicleType: '20ft',
        budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1', timeline: {status: at}, agreedFarePaise: paise, businessId: 'o1');
    BizExpense ex(String id, String kind, int paise, DateTime d) => BizExpense(id: id, kind: kind, amountPaise: paise, date: d);

    test('six months, freight plus costs by kind, other months and cancelled trips left out', () {
      final m = spendDashboard(
        [trip('a', DateTime(2026, 10, 2), 100000), trip('b', DateTime(2026, 9, 20), 250000), trip('c', DateTime(2026, 9, 21), 5000, status: 'cancelled'), trip('old', DateTime(2025, 1, 1), 999)],
        [ex('1', 'fuel', 30000, DateTime(2026, 10, 3)), ex('2', 'toll', 7000, DateTime(2026, 10, 4)), ex('3', 'fuel', 1000, DateTime(2026, 9, 2)), ex('x', 'fuel', 5, DateTime(2024, 1, 1))],
        now,
      );
      expect(m.map((e) => e.month), ['2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10']);
      expect(m.last.freightPaise, 100000);
      expect(m.last.byKind, {'fuel': 30000, 'toll': 7000});
      expect(m.last.totalPaise, 137000);
      expect((m[4].freightPaise, m[4].totalPaise), (250000, 251000));
      expect(m.first.totalPaise, 0);
    });

    test('add validates kind, amount, note and future dates; list newest first; delete', () async {
      await BusinessOpsService.addExpense('o1', kind: 'fuel', amountPaise: 450000, date: DateTime(2026, 10, 1), costCenter: 'Plant 2', now: now);
      await BusinessOpsService.addExpense('o1', kind: 'toll', amountPaise: 30000, date: DateTime(2026, 10, 5), note: 'Kherki', now: now);
      await expectLater(() => BusinessOpsService.addExpense('o1', kind: 'beer', amountPaise: 5, date: now, now: now), throwsA(isA<BusinessOpsException>()));
      await expectLater(() => BusinessOpsService.addExpense('o1', kind: 'fuel', amountPaise: 0, date: now, now: now), throwsA(isA<BusinessOpsException>()));
      await expectLater(() => BusinessOpsService.addExpense('o1', kind: 'fuel', amountPaise: 5, date: DateTime(2026, 12, 1), now: now), throwsA(isA<BusinessOpsException>().having((e) => e.reason, 'r', 'future')));
      final list = await BusinessOpsService.watchExpenses('o1').first;
      expect(list.map((e) => e.kind), ['toll', 'fuel']);
      await BusinessOpsService.deleteExpense(list.first.id);
      expect((await BusinessOpsService.watchExpenses('o1').first).length, 1);
    });

    testWidgets('dashboard screen shows the month totals and adds an expense for an accounts user', (tester) async {
      await tester.runAsync(() async {
        await BusinessOpsService.addExpense('o1', kind: 'toll', amountPaise: 30000, date: DateTime(2026, 10, 5), now: DateTime(2026, 10, 6));
      });
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: SpendDashboardScreen(context: const BizContext('o1', BizRole.accounts), now: () => DateTime(2026, 10, 6)))));
      await settle(tester);
      expect(find.byKey(const ValueKey('spend_2026-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('spendTotal_2026-10')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bizAddExpense')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bizKind_fuel')));
      await tester.enterText(find.byKey(const ValueKey('bizAmount')), '1500');
      await tester.tap(find.byKey(const ValueKey('bizExpenseSave')));
      await settle(tester);
      final all = (await tester.runAsync(() => BusinessOpsService.watchExpenses('o1').first))!;
      expect(all.map((e) => (e.kind, e.amountPaise)).toSet(), {('toll', 30000), ('fuel', 150000)});
    });

    testWidgets('a viewer sees the dashboard but not the add button', (tester) async {
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: SpendDashboardScreen(context: const BizContext('o1', BizRole.viewer), now: () => DateTime(2026, 10, 6)))));
      await settle(tester);
      expect(find.byKey(const ValueKey('bizAddExpense')), findsNothing);
    });
  });

  group('business support (BIZ15)', () {
    test('a company ticket carries the company id, starts at high priority, and is listed for the company', () async {
      final id = await SupportService.create(category: TicketCategory.other, subject: 'Invoice question', businessId: 'o1');
      final plain = await SupportService.create(category: TicketCategory.other, subject: 'Plain question');
      final urgent = await SupportService.create(category: TicketCategory.safety, subject: 'Accident', businessId: 'o1');
      final t = SupportTicket.fromDoc(await db.collection('tickets').doc(id).get());
      expect((t.businessId, t.priority), ('o1', TicketPriority.high));
      expect(SupportTicket.fromDoc(await db.collection('tickets').doc(plain).get()).priority, TicketPriority.normal);
      expect(SupportTicket.fromDoc(await db.collection('tickets').doc(urgent).get()).priority, TicketPriority.urgent);
      expect((await SupportService.watchForBusiness('o1').first).map((x) => x.id).toSet(), {id, urgent});
    });
  });

  group('screens by role', () {
    Future<void> hub(WidgetTester tester, String role) async {
      await tester.runAsync(() async {
        await member('m9', role, '+919800000019');
        signIn('m9');
      });
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: BusinessHubScreen())));
      await settle(tester);
    }

    testWidgets('manager: approvals, spend, pool, support; not team or profile', (tester) async {
      await hub(tester, BizRole.manager);
      for (final k in ['hubApprovals', 'hubSpend', 'hubContracts', 'hubPool', 'hubSupport', 'hubStatement']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(find.byKey(const ValueKey('hubTeam')), findsNothing);
      expect(find.byKey(const ValueKey('hubBusiness')), findsNothing);
    });

    testWidgets('viewer: statements and spend, nothing that posts or manages', (tester) async {
      await hub(tester, BizRole.viewer);
      expect(find.byKey(const ValueKey('hubStatement')), findsOneWidget);
      expect(find.byKey(const ValueKey('hubSpend')), findsOneWidget);
      for (final k in ['hubApprovals', 'hubPool', 'hubSupport', 'hubBulk', 'hubTeam']) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
    });

    testWidgets('owner sees everything including the team', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      signIn('o1');
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: BusinessHubScreen())));
      await settle(tester);
      for (final k in ['hubBusiness', 'hubTeam', 'hubStatement', 'hubApprovals', 'hubSpend', 'hubContracts', 'hubPool', 'hubSupport', 'hubBulk', 'hubShipments']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('team screen: invite with a role and change a member role', (tester) async {
      await tester.runAsync(() => member('m1', BizRole.booker, '+919800000021'));
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: BusinessTeamScreen())));
      await settle(tester);
      expect(find.text('Booker'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('teamRoleMenu_m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accounts').last);
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('business_members').doc('o1_m1').get()))!.data()!['role'], 'accounts');
    });
  });
}
