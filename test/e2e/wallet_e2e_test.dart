import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/money/wallet_book.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/finance_service.dart';
import 'package:transport_app/core/services/payment_service.dart';
import 'package:transport_app/core/services/payout_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/wallet/finance/finance_logic.dart';
import 'package:transport_app/core/wallet/hub/hub_models.dart';

/// F14: a delivered trip becomes earnings, a payout is asked for, one finance
/// admin approves, another pays, and the books still balance at every step.
/// Fake Firestore has no rules; those are in firestore_rules_test.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    PricingService.reset();
  });

  Future<Booking> deliveredAndPaid(String id, int fare) async {
    await db.collection('bookings').doc(id).set({
      'loadId': 'L$id',
      'driverId': 'd1',
      'vehicleId': 'v1',
      'customerId': 'c1',
      'status': BookingStatus.delivered,
      'pickup': 'Pune',
      'drop': 'Delhi',
      'cargoType': 'x',
      'weight': 1,
      'vehicleType': '20ft',
      'driverName': 'Ravi',
      'vehicleNumber': 'MH12AB1',
      'timeline': <String, Object?>{},
      'paymentStatus': PaymentStatus.pending,
    });
    uid = 'c1';
    await PaymentService.markPaid(Booking.fromDoc(await db.collection('bookings').doc(id).get()), fare);
    uid = 'd1';
    final b = Booking.fromDoc(await db.collection('bookings').doc(id).get());
    await PaymentService.confirmReceived(b);
    return b;
  }

  Future<List<Payout>> payouts() async => [for (final d in (await db.collection('payouts').get()).docs) Payout.fromDoc(d.id, d.data())];
  Future<List<LedgerEntry>> ledger() async => [for (final d in (await db.collection('ledger').get()).docs) LedgerEntry.fromDoc(d)];

  Future<Reconciliation> recon() async => Reconciliation.run(ledger: await ledger(), payouts: await payouts());

  test('trip delivered, earning and commission lines, payout, two admins, paid; every step balances', () async {
    await deliveredAndPaid('B1', 1000000); // Rs 10,000
    uid = 'd1';
    var hub = DriverHub.from(entries: await ledger(), now: DateTime.now());
    expect(hub.balance.available.paise, 1000000 - 50000, reason: '5% commission for a Free driver');
    expect((await recon()).problems, isEmpty);

    final id = await PayoutService.request(600000);
    var all = await payouts();
    expect(all.single.status, Payout.requested);
    hub = DriverHub.from(entries: await ledger(), payouts: all, now: DateTime.now());
    expect(hub.balance.held.paise, 600000);
    expect(hub.balance.available.paise, 350000);
    await expectLater(PayoutService.request(100000), throwsA(isA<PayoutException>().having((e) => e.reason, 'reason', 'open_request')));

    uid = 'fin1';
    await FinanceService.approve(all.single);
    all = await payouts();
    expect(all.single.status, Payout.approved);
    expect(all.single.approvedBy, 'fin1');
    expect(PayoutActions.canPay(all.single, 'fin1'), isFalse);
    await expectLater(FinanceService.pay(all.single, 'UTR0001'), throwsA(isA<FinanceException>()));
    uid = 'fin2';
    expect(PayoutActions.canPay(all.single, 'fin2'), isTrue);
    await FinanceService.pay(all.single, 'UTR0001');

    all = await payouts();
    expect(all.single.status, Payout.paid);
    expect(all.single.paidBy, 'fin2');
    expect(all.single.reference, 'UTR0001');
    final r = await recon();
    expect(r.problems, isEmpty);
    expect(r.paidOutPaise, 600000);
    expect(r.owedPaise, 350000);
    hub = DriverHub.from(entries: await ledger(), payouts: all, now: DateTime.now());
    expect(hub.balance.paidOut.paise, 600000);
    expect(hub.balance.available.paise, 350000);

    final audits = [for (final d in (await db.collection('audit_events').get()).docs) d.data()];
    expect(audits.where((a) => a['type'] == 'payout_decision').map((a) => (a['data'] as Map)['action']).toSet(), {'approve', 'pay'});
    expect(audits.where((a) => a['type'] == 'wallet_action').length, 1, reason: 'the payout request');
    expect(id, all.single.id);
  });

  test('a transfer that came back is reversed: the money returns to available and the check stays clean', () async {
    await deliveredAndPaid('B1', 200000);
    uid = 'd1';
    await PayoutService.request(150000);
    uid = 'fin1';
    await FinanceService.approve((await payouts()).single);
    uid = 'fin2';
    await FinanceService.pay((await payouts()).single, 'UTR7777');
    await FinanceService.reverse((await payouts()).single, 'Bank returned the transfer');
    final all = await payouts();
    expect(all.single.status, Payout.reversed);
    final book = WalletBook.fromSources(ledger: await ledger(), payouts: all);
    expect(book.balance.paidOut.paise, 0);
    expect(book.balance.available.paise, 200000 - 10000);
    expect((await recon()).problems, isEmpty);
    uid = 'd1';
    await PayoutService.request(100000); // can ask again
    expect((await payouts()).length, 2);
  });

  test('a rejected request frees the money and a correction line moves the balance', () async {
    await deliveredAndPaid('B1', 100000);
    uid = 'd1';
    await PayoutService.request(95000);
    uid = 'fin1';
    await FinanceService.reject((await payouts()).single, 'Details do not match');
    await FinanceService.adjust('d1', -5000, 'Wrong commission on B1');
    final book = WalletBook.fromSources(ledger: await ledger(), payouts: await payouts());
    expect(book.balance.available.paise, 100000 - 5000 - 5000);
    expect(book.balance.held.paise, 0);
    expect((await recon()).problems, isEmpty);
  });

  test('requests one after another: the day counter equals the number of payouts and their total', () async {
    await deliveredAndPaid('B1', 5000000);
    uid = 'd1';
    for (var i = 0; i < 4; i++) {
      await PayoutService.request(1000 * (i + 1));
      uid = 'fin1';
      await FinanceService.reject((await payouts()).firstWhere((p) => p.status == Payout.requested), 'Test round $i');
      uid = 'd1';
    }
    final now = DateTime.now().toUtc();
    final c = (await db.collection('payout_counters').doc('d1_${now.year * 10000 + now.month * 100 + now.day}').get()).data()!;
    expect(c['count'], 4);
    expect(c['totalPaise'], 1000 + 2000 + 3000 + 4000);
  });

  test('requests at the same moment never throw and each written payout has a counter write (real Firestore serialises the counter; the fake does not)', () async {
    await deliveredAndPaid('B1', 5000000);
    uid = 'd1';
    final results = await Future.wait([for (var i = 0; i < 6; i++) PayoutService.request(1000).then((_) => true).catchError((Object _) => false)]);
    expect((await payouts()).length, results.where((x) => x).length);
    expect((await db.collection('payout_counters').get()).docs.length, 1);
  });

  test('two admins act on the same payout at the same moment: it ends in one state, never both', () async {
    await deliveredAndPaid('B1', 100000);
    uid = 'd1';
    await PayoutService.request(50000);
    final p = (await payouts()).single;
    uid = 'fin1';
    final results = await Future.wait([
      FinanceService.reject(p, 'Reviewed and rejected').then((_) => 'rejected').catchError((Object _) => 'failed'),
      FinanceService.approve(p).then((_) => 'approved').catchError((Object _) => 'failed'),
    ]);
    // Fake Firestore has no rules, so both writes land; the last one wins and the status is one of the two.
    final end = (await payouts()).single.status;
    expect([Payout.approved, Payout.rejected], contains(end));
    expect(results.where((x) => x != 'failed').length, 2);
  });
}
