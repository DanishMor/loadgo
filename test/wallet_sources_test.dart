import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/money/wallet_book.dart';

/// F8: the stored data (ledger lines and payout requests) turns into one book.
void main() {
  LedgerEntry l(String id, String type, int a) => LedgerEntry(id: id, driverId: 'd1', bookingId: 'B', type: type, amountPaise: a);
  Payout p(String id, int a, String status) => Payout(id: id, driverId: 'd1', amountPaise: a, status: status);

  final ledger = [l('B1_trip_earning', LedgerType.tripEarning, 100000), l('B1_platform_commission', LedgerType.platformCommission, -10000)];

  test('open payouts hold money, paid ones are paid out, rejected ones are released, reversed ones come back', () {
    final b = WalletBook.fromSources(ledger: ledger, payouts: [
      p('p1', 20000, Payout.requested),
      p('p2', 10000, Payout.approved),
      p('p3', 30000, Payout.paid),
      p('p4', 5000, Payout.rejected),
      p('p5', 7000, Payout.reversed),
    ]).balance;
    expect(b.held.paise, 30000); // p1 + p2
    expect(b.paidOut.paise, 30000); // p3
    expect(b.available.paise, 90000 - 20000 - 10000 - 30000 - 0 - 0); // p4 and p5 are back
    expect(b.isSound, isTrue);
    expect(b.lifetime.paise, 90000);
  });

  test('an admin correction counts, a payout twice in the data counts once', () {
    final b = WalletBook.fromSources(
      ledger: [...ledger, l('adj_x', LedgerType.adjustment, -2500)],
      payouts: [p('p1', 1000, Payout.paid), p('p1', 1000, Payout.paid)],
    ).balance;
    expect(b.available.paise, 90000 - 2500 - 1000);
    expect(b.paidOut.paise, 1000);
  });

  test('WalletSummary includes corrections in the net', () {
    final s = WalletSummary.of([...ledger, l('adj_x', LedgerType.adjustment, 500)]);
    expect(s.adjustments, 500);
    expect(s.net, 90500);
  });

  test('Payout.fromDoc survives missing, wrong and unknown values', () {
    final a = Payout.fromDoc('x', {'driverId': 5, 'amountPaise': 'lots', 'status': 'weird', 'createdAt': 'yesterday', 'approvedBy': 7, 'reference': ['u']});
    expect(a.driverId, '');
    expect(a.amountPaise, 0);
    expect(a.status, Payout.requested);
    expect(a.createdAt, isNull);
    expect(a.approvedBy, isNull);
    expect(a.reference, isNull);
    final b = Payout.fromDoc('y', {'driverId': 'd1', 'amountPaise': 5000, 'status': 'approved', 'approvedBy': 'fin1'});
    expect(b.isOpen, isTrue);
    expect(b.approvedBy, 'fin1');
  });

  test('the older balance view counts approved payouts as still requested and reversed as not paid', () {
    final w = WalletBalances.of(ledger: ledger, bookings: const [], payouts: [p('a', 1000, Payout.approved), p('b', 2000, Payout.paid), p('c', 4000, Payout.reversed)]);
    expect(w.requested, 1000);
    expect(w.paidOut, 2000);
    expect(w.available, 90000 - 1000 - 2000);
  });
}
