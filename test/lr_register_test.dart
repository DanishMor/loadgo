import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/bilty/lr_register.dart';
import 'package:transport_app/core/bilty/lr_register_screen.dart';
import 'package:transport_app/core/bilty/lr_service.dart';
import 'package:transport_app/core/l10n/l10n.dart';

import 'test_utils.dart';

/// MASTER-6 Task 31: the LR register.
void main() {
  final now = DateTime(2026, 10, 9, 12);

  LrPublic lr(int seq, int version, {String status = 'issued', String route = 'Delhi - Jaipur', String consignor = 'Acme', String vehicle = 'MH12AB1234', int year = 2026, String issuer = 'tr1'}) =>
      LrPublic.fromDoc('${issuer}_${year}_${seq}_v$version', {
        'bookingId': 'b$seq', 'issuerId': issuer, 'issuerRole': 'transporter', 'customerId': 'c1', 'lrNo': 'TR-$year-${seq.toString().padLeft(6, '0')}', 'seq': seq, 'year': year,
        'version': version, 'status': status, 'pickup': route.split(' - ').first, 'drop': route.split(' - ').last, 'route': route, 'goods': 'Rice', 'consignorName': consignor,
        'vehicleNumber': vehicle, 'date': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });

  LrShare share(String token, String lrId, {String copy = 'consignee', DateTime? expires, bool revoked = false, int views = 0}) => LrShare(token: token, lrId: lrId, copyType: copy, expiresAt: expires, revoked: revoked, views: views);

  test('one row per LR number: the issued version, else the newest; newest LR first; links of every version', () {
    final all = [lr(1, 1, status: 'superseded'), lr(1, 2), lr(2, 1, status: 'cancelled'), lr(3, 1), lr(3, 2, status: 'superseded'), lr(1, 1, year: 2025, status: 'issued')];
    final rows = LrRegister.rows(all, [share('t1', 'tr1_2026_1_v1'), share('t2', 'tr1_2026_1_v2')]);
    expect(rows.map((r) => r.lr.lrNo), ['TR-2026-000003', 'TR-2026-000002', 'TR-2026-000001', 'TR-2025-000001']);
    final r1 = rows.firstWhere((r) => r.lr.lrNo == 'TR-2026-000001');
    expect((r1.lr.version, r1.versions, r1.shares.length), (2, 2, 2));
    final r3 = rows.firstWhere((r) => r.lr.lrNo == 'TR-2026-000003');
    expect(r3.lr.version, 1); // the issued one, not the newer superseded
    expect(rows.firstWhere((r) => r.lr.lrNo == 'TR-2026-000002').lr.status, 'cancelled'); // only version: shown as it is
  });

  test('link states: active, expired, stopped; the counts follow', () {
    final r = LrRow(lr(1, 1), 1, [
      share('a', 'x', expires: now.add(const Duration(days: 1))),
      share('b', 'x', expires: now.subtract(const Duration(days: 1))),
      share('c', 'x', expires: now.add(const Duration(days: 3)), revoked: true),
      share('d', 'x'), // no end date: live
    ]);
    expect([for (final s in r.shares) LrRegister.stateOf(s, now).name], ['active', 'expired', 'revoked', 'active']);
    expect((r.active(now), r.expired(now), r.revoked()), (2, 1, 1));
  });

  test('search: every word must match the number, route, goods, party, vehicle or driver; status filter; counts', () {
    final rows = LrRegister.rows([lr(1, 1, consignor: 'Anil Traders'), lr(2, 1, route: 'Pune - Mumbai', vehicle: 'KA01CD5678'), lr(3, 1, status: 'cancelled')], const []);
    expect(LrRegister.filter(rows, query: '').length, 3);
    expect(LrRegister.filter(rows, query: 'anil traders').map((r) => r.lr.seq), [1]);
    expect(LrRegister.filter(rows, query: 'mumbai').map((r) => r.lr.seq), [2]);
    expect(LrRegister.filter(rows, query: 'ka01cd5678').map((r) => r.lr.seq), [2]);
    expect(LrRegister.filter(rows, query: 'TR-2026-000003').map((r) => r.lr.seq), [3]);
    expect(LrRegister.filter(rows, query: 'rice mumbai').map((r) => r.lr.seq), [2]);
    expect(LrRegister.filter(rows, query: 'nothing at all'), isEmpty);
    expect(LrRegister.filter(rows, status: 'cancelled').map((r) => r.lr.seq), [3]);
    expect(LrRegister.counts(rows), {null: 3, 'issued': 2, 'cancelled': 1, 'superseded': 0});
  });

  Widget screen({List<LrPublic>? lrs, List<LrShare>? shares, Future<void> Function(LrShare, LrPublic)? revoke}) => LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: LrRegisterScreen(lrs: Stream.value(lrs ?? [lr(1, 1), lr(2, 1, status: 'cancelled', route: 'Pune - Mumbai')]), shares: Stream.value(shares ?? const []), now: () => now, revoke: revoke)),
      );

  testWidgets('the register lists LRs with status and link counts; search and the status chips narrow it', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screen(shares: [share('t1', 'tr1_2026_1_v1', expires: now.add(const Duration(days: 1)))]));
    await settle(tester);
    expect(find.byKey(const ValueKey('lrRow_TR-2026-000001')), findsOneWidget);
    expect(find.text('Links: 1 active, 0 expired, 0 stopped'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('lrrSearch')), 'mumbai');
    await tester.pump();
    expect(find.byKey(const ValueKey('lrRow_TR-2026-000001')), findsNothing);
    expect(find.byKey(const ValueKey('lrRow_TR-2026-000002')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('lrrSearch')), '');
    await tester.tap(find.byKey(const ValueKey('lrrStatus_cancelled')));
    await tester.pump();
    expect(find.byKey(const ValueKey('lrRow_TR-2026-000001')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('lrrSearch')), 'zzz');
    await tester.pump();
    expect(find.byKey(const ValueKey('lrrNoMatch')), findsOneWidget);
  });

  testWidgets('opening an LR lists its links by state and stops an active one', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    LrShare? stopped;
    await tester.pumpWidget(screen(
      shares: [
        share('aaaaaa111111', 'tr1_2026_1_v1', expires: now.add(const Duration(days: 1)), views: 3),
        share('bbbbbb222222', 'tr1_2026_1_v1', expires: now.subtract(const Duration(days: 1))),
        share('cccccc333333', 'tr1_2026_1_v1', revoked: true, expires: now.add(const Duration(days: 5))),
        share('dddddd444444', 'tr1_2026_1_v1', copy: 'verify', expires: now.add(const Duration(days: 100))),
      ],
      revoke: (s, l) async => stopped = s,
    ));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('lrRow_TR-2026-000001')));
    await settle(tester);
    expect(find.byKey(const ValueKey('lrLink_aaaaaa111111')), findsOneWidget);
    expect(find.textContaining('active'), findsWidgets);
    expect(find.byKey(const ValueKey('lrLink_bbbbbb222222')), findsOneWidget);
    expect(find.byKey(const ValueKey('lrLink_cccccc333333')), findsOneWidget);
    expect(find.byKey(const ValueKey('lrLink_dddddd444444')), findsNothing); // the QR verify link is not a link the person made
    expect(find.byKey(const ValueKey('lrRevoke_bbbbbb222222')), findsNothing);
    expect(find.byKey(const ValueKey('lrRevoke_cccccc333333')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lrRevoke_aaaaaa111111')));
    await settle(tester);
    expect(stopped?.token, 'aaaaaa111111');
  });

  testWidgets('no LR yet says so', (tester) async {
    await tester.pumpWidget(screen(lrs: const []));
    await settle(tester);
    expect(find.text('You have not made an LR yet.'), findsOneWidget);
  });
}
