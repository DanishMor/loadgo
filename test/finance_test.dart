import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_finance_screen.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/finance_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/wallet/finance/finance_logic.dart';

/// F12: the finance dashboard (logic, service and screen).
void main() {
  final now = DateTime(2026, 10, 14, 15);
  Payout p(String id, String driver, int a, String status, {String? approvedBy, String? paidBy, DateTime? at}) =>
      Payout(id: id, driverId: driver, amountPaise: a, status: status, approvedBy: approvedBy, paidBy: paidBy, createdAt: at ?? now);
  LedgerEntry l(String id, String driver, String type, int a) => LedgerEntry(id: id, driverId: driver, bookingId: 'b', type: type, amountPaise: a);

  group('maker-checker rules in the app', () {
    test('only a different admin can mark an approved payout paid', () {
      final approved = p('p1', 'd1', 1000, Payout.approved, approvedBy: 'fin1');
      expect(PayoutActions.canPay(approved, 'fin1'), isFalse);
      expect(PayoutActions.canPay(approved, 'fin2'), isTrue);
      expect(PayoutActions.canPay(approved, null), isFalse);
      expect(PayoutActions.whyNotPay(approved, 'fin1'), 'finSameAdmin');
      expect(PayoutActions.whyNotPay(approved, 'fin2'), isNull);
      expect(PayoutActions.canPay(p('p2', 'd1', 1000, Payout.requested), 'fin2'), isFalse, reason: 'must be approved first');
      expect(PayoutActions.canPay(p('p3', 'd1', 1000, Payout.approved), 'fin2'), isFalse, reason: 'an approval with no approver is not trusted');
    });

    test('approve, reject and reverse follow the status', () {
      expect(PayoutActions.canApprove(p('a', 'd', 1, Payout.requested)), isTrue);
      expect(PayoutActions.canApprove(p('a', 'd', 1, Payout.approved)), isFalse);
      expect(PayoutActions.canReject(p('a', 'd', 1, Payout.requested)), isTrue);
      expect(PayoutActions.canReject(p('a', 'd', 1, Payout.approved)), isTrue);
      expect(PayoutActions.canReject(p('a', 'd', 1, Payout.paid)), isFalse);
      expect(PayoutActions.canReverse(p('a', 'd', 1, Payout.paid)), isTrue);
      expect(PayoutActions.canReverse(p('a', 'd', 1, Payout.requested)), isFalse);
      expect(stageOf(p('a', 'd', 1, Payout.reversed)), PayoutStage.closed);
      expect(stageOf(p('a', 'd', 1, Payout.paid)), PayoutStage.done);
    });

    test('the finance area is for super and finance only', () {
      expect(staffCan('finance', 'adminFinance'), isTrue);
      expect(staffCan('super', 'adminFinance'), isTrue);
      for (final r in ['support', 'ops', 'verifier']) {
        expect(staffCan(r, 'adminFinance'), isFalse, reason: r);
      }
    });
  });

  group('anomalies', () {
    test('big payouts, new payout details with a big amount, many in one day', () {
      final list = AnomalyRules.detect([
        p('big', 'd1', 6000000, Payout.requested),
        p('small', 'd2', 5000, Payout.requested),
        p('new', 'd3', 1500000, Payout.requested),
        p('old', 'd4', 1500000, Payout.requested),
        p('m1', 'd5', 100, Payout.requested),
        p('m2', 'd5', 100, Payout.requested),
        p('m3', 'd5', 100, Payout.paid),
        p('rej', 'd6', 9000000, Payout.rejected),
      ], detailsChangedAt: {'d3': now.subtract(const Duration(days: 2)), 'd4': now.subtract(const Duration(days: 30))}, now: now);
      Set<String> ids(AnomalyKind k) => {for (final a in list) if (a.kind == k) a.payoutId};
      expect(ids(AnomalyKind.bigPayout), {'big'});
      expect(ids(AnomalyKind.newAccountBig), {'new'});
      expect(ids(AnomalyKind.manyInOneDay), {'m1', 'm2', 'm3'});
    });

    test('no payouts, no flags', () {
      expect(AnomalyRules.detect(const [], now: now), isEmpty);
    });
  });

  group('daily reconciliation', () {
    test('a clean book balances; the owed and paid totals are right', () {
      final r = Reconciliation.run(ledger: [
        l('a1', 'd1', LedgerType.tripEarning, 100000),
        l('a2', 'd1', LedgerType.platformCommission, -10000),
        l('b1', 'd2', LedgerType.tripEarning, 50000),
      ], payouts: [
        p('p1', 'd1', 30000, Payout.paid),
        p('p2', 'd2', 20000, Payout.requested),
      ], summaries: {'d1': 90000, 'd2': 50000});
      expect(r.problems, isEmpty);
      expect(r.paidOutPaise, 30000);
      expect(r.owedPaise, 60000 + 30000 + 20000, reason: "available plus held");
    });

    test('more paid than earned, a wrong summary and a payout with no earnings are all found', () {
      final r = Reconciliation.run(ledger: [l('a1', 'd1', LedgerType.tripEarning, 10000), l('b1', 'd2', LedgerType.tripEarning, 5000)], payouts: [
        p('p1', 'd1', 25000, Payout.paid),
        p('p3', 'd3', 100, Payout.requested),
      ], summaries: {'d2': 4000});
      final byId = {for (final x in r.rows) x.driverId: x};
      expect(byId['d1']!.overdrawn, isTrue);
      expect(byId['d2']!.summaryMismatch, isTrue);
      expect(byId['d3']!.overdrawn, isTrue);
      expect(r.problems.length, 3);
      expect(r.toCsv(), contains('overdrawn'));
      expect(r.toCsv(), contains('summary_mismatch'));
    });

    test('a reversed payout puts the money back; a rejected one never took it', () {
      final r = Reconciliation.run(ledger: [l('a1', 'd1', LedgerType.tripEarning, 10000)], payouts: [p('p1', 'd1', 4000, Payout.reversed), p('p2', 'd1', 3000, Payout.rejected)]);
      expect(r.problems, isEmpty);
      expect(r.rows.single.balance.available.paise, 10000);
      expect(r.owedPaise, 10000);
    });

    test('corrections count and the CSV has a header and one line per person', () {
      final r = Reconciliation.run(ledger: [l('a1', 'd1', LedgerType.tripEarning, 10000), l('adj_x', 'd1', LedgerType.adjustment, -2500)], payouts: const []);
      expect(r.rows.single.ledgerNetPaise, 7500);
      final csv = r.toCsv().trim().split('\n');
      expect(csv.first, Reconciliation.csvHeader);
      expect(csv.length, 2);
    });

    test('queue CSV never holds a formula', () {
      final csv = payoutQueueCsv([p('=cmd', '+d1', 1000, Payout.paid, approvedBy: 'fin1', paidBy: 'fin2')]);
      expect(csv.split('\n')[1].startsWith("'=cmd"), isTrue);
      expect(csv, contains("'+d1"));
    });
  });

  group('FinanceService', () {
    late FakeFirebaseFirestore db;
    setUp(() {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'fin1');
    });

    Future<Payout> seed(String id, String status, {String? approvedBy}) async {
      await db.collection('payouts').doc(id).set({'driverId': 'd1', 'amountPaise': 5000, 'status': status, 'approvedBy': ?approvedBy});
      return Payout.fromDoc(id, (await db.collection('payouts').doc(id).get()).data()!);
    }

    test('approve then pay (by another admin) writes the fields and one audit line each', () async {
      await FinanceService.approve(await seed('p1', Payout.requested));
      var d = (await db.collection('payouts').doc('p1').get()).data()!;
      expect(d['status'], Payout.approved);
      expect(d['approvedBy'], 'fin1');
      final approved = Payout.fromDoc('p1', d);
      await expectLater(FinanceService.pay(approved, 'UTR123456'), throwsA(isA<FinanceException>().having((e) => e.key, 'key', 'finSameAdmin')));
      Backend.useFakes(db: db, uid: () => 'fin2');
      await expectLater(FinanceService.pay(approved, 'ab'), throwsA(isA<FinanceException>().having((e) => e.key, 'key', 'finNeedRef')));
      await FinanceService.pay(approved, '  UTR123456 ');
      d = (await db.collection('payouts').doc('p1').get()).data()!;
      expect(d['status'], Payout.paid);
      expect(d['paidBy'], 'fin2');
      expect(d['reference'], 'UTR123456');
      final audits = (await db.collection('audit_events').get()).docs.map((x) => x.data()).toList();
      expect(audits.length, 2);
      expect(audits.every((a) => a['type'] == 'payout_decision' && a['targetId'] == 'p1'), isTrue);
      expect(audits.map((a) => (a['data'] as Map)['action']).toSet(), {'approve', 'pay'});
    });

    test('reject and reverse need reasons and write them', () async {
      await expectLater(FinanceService.reject(await seed('p2', Payout.requested), 'no'), throwsA(isA<FinanceException>()));
      await FinanceService.reject(await seed('p2', Payout.requested), 'Name does not match');
      expect((await db.collection('payouts').doc('p2').get()).data()!['reason'], 'Name does not match');
      await expectLater(FinanceService.reverse(await seed('p3', Payout.paid), 'oops'), throwsA(isA<FinanceException>()), reason: 'five letters at least');
      await FinanceService.reverse(await seed('p3', Payout.paid), 'Transfer bounced');
      final d = (await db.collection('payouts').doc('p3').get()).data()!;
      expect(d['status'], Payout.reversed);
      expect(d['reversedBy'], 'fin1');
    });

    test('freeze and unfreeze keep the reason and log it; adjustments are signed lines with a safe id', () async {
      await FinanceService.setFrozen('d1', true, 'Disputed trip');
      var f = (await db.collection('wallet_freezes').doc('d1').get()).data()!;
      expect(f['frozen'], isTrue);
      expect(f['reason'], 'Disputed trip');
      await FinanceService.setFrozen('d1', false, 'Cleared');
      f = (await db.collection('wallet_freezes').doc('d1').get()).data()!;
      expect(f['frozen'], isFalse);
      await expectLater(FinanceService.setFrozen('', true, 'Disputed'), throwsA(isA<FinanceException>()));
      await FinanceService.adjust('d1', -2500, 'Wrong commission on B7');
      final line = (await db.collection('ledger').get()).docs.single;
      expect(RegExp(r'^adj_[A-Za-z0-9]{8,40}$').hasMatch(line.id), isTrue, reason: line.id);
      expect(line.data()['amountPaise'], -2500);
      expect(line.data()['type'], 'adjustment');
      await expectLater(FinanceService.adjust('d1', 0, 'Nothing to do'), throwsA(isA<FinanceException>()));
      await expectLater(FinanceService.adjust('d1', 100000000001, 'Too much money'), throwsA(isA<FinanceException>()));
      await expectLater(FinanceService.adjust('d1', 100, 'xx'), throwsA(isA<FinanceException>()));
      final types = (await db.collection('audit_events').get()).docs.map((d) => d.data()['type']).toList();
      expect(types.where((t) => t == 'wallet_freeze').length, 2);
      expect(types.where((t) => t == 'wallet_adjust').length, 1);
    });

    test('two adjustments in the same moment do not share an id', () async {
      await Future.wait([FinanceService.adjust('d1', 100, 'First correction'), FinanceService.adjust('d1', 200, 'Second correction')]);
      expect((await db.collection('ledger').get()).docs.length, 2);
    });
  });

  group('screen', () {
    Widget host(Widget w, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1.0}) {
      final language = ValueNotifier(lang);
      final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
      return LanguageScope(
        notifier: language,
        child: MaterialApp(
          theme: AppTheme.build(b),
          builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true), child: Directionality(textDirection: dir, child: child!)),
          home: w,
        ),
      );
    }

    AdminFinanceScreen screen({List<Payout>? payouts, String me = 'fin2'}) => AdminFinanceScreen(
          payouts: () => Stream.value(payouts ??
              [
                p('r1', 'd1', 6000000, Payout.requested),
                p('a1', 'd2', 5000, Payout.approved, approvedBy: 'fin1'),
                p('a2', 'd3', 7000, Payout.approved, approvedBy: 'fin2'),
                p('x1', 'd4', 9000, Payout.paid, approvedBy: 'fin1', paidBy: 'fin2'),
              ]),
          ledger: () => Stream.value([l('e1', 'd1', LedgerType.tripEarning, 100000)]),
          summaries: () => Stream.value(const {}),
          detailsChanged: () => Stream.value(const {}),
          me: () => me,
          now: () => now,
        );

    testWidgets('the queue shows the right buttons for the right person, with warnings', (t) async {
      await t.pumpWidget(host(screen()));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('finApprove_r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('finAnomaly_r1_bigPayout')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('finStage_waitingPayment')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('finPay_a1')), findsOneWidget, reason: 'fin2 may pay what fin1 approved');
      expect(find.byKey(const ValueKey('finPay_a2')), findsNothing, reason: 'fin2 approved this one');
      expect(find.byKey(const ValueKey('finWhy_a2')), findsOneWidget);
      expect(find.byKey(const ValueKey('finReject_a1')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('finStage_done')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('finReverse_x1')), findsOneWidget);
    });

    testWidgets('daily check tab: balanced book says so; a problem is listed', (t) async {
      await t.pumpWidget(host(screen(payouts: [p('p1', 'd1', 5000, Payout.requested)])));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('finTabRecon')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('finReconOk')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(host(screen(payouts: [p('p9', 'd1', 500000, Payout.paid)])));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('finTabRecon')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('finRecon_d1')), findsOneWidget);
    });

    for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.urdu]) {
      for (final b in Brightness.values) {
        testWidgets('fits 360x640 at 2.0x text on all three tabs: ${lang.name} ${b.name}', (t) async {
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(host(screen(), lang: lang, b: b, scale: 2.0));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          for (final tab in ['finTabRecon', 'finTabTools', 'finTabQueue']) {
            await t.ensureVisible(find.byKey(ValueKey(tab)));
            await t.pumpAndSettle();
            await t.tap(find.byKey(ValueKey(tab)));
            await t.pumpAndSettle();
            await t.drag(find.byType(ListView).first, const Offset(0, -2000));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: tab);
          }
        });
      }
    }
  });
}
