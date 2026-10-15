import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/money/money.dart';
import 'package:transport_app/core/money/wallet_book.dart';

/// F7: the money core. Pure Dart, no Firestore.
void main() {
  group('Money', () {
    test('plain arithmetic, comparison and debug text', () {
      expect((Money(150) + Money(250)).paise, 400);
      expect((Money(150) - Money(250)).paise, -100);
      expect((-Money(5)).paise, -5);
      expect(Money(-7).abs.paise, 7);
      expect(Money(-7).atLeastZero, Money.zero);
      expect(Money(3) < Money(4) && Money(4) > Money(3) && Money(4) >= Money(4) && Money(4) <= Money(4), isTrue);
      expect(Money.rupees(12).paise, 1200);
      expect(Money(12345).debug, 'Rs 123.45');
      expect(Money(-50).debug, '-Rs 0.50');
      expect(Money(5).debug, 'Rs 0.05');
    });

    test('parse never throws: junk becomes 0, huge numbers are limited', () {
      expect(Money.parse(null), Money.zero);
      expect(Money.parse('12'), Money.zero);
      expect(Money.parse(double.nan), Money.zero);
      expect(Money.parse(double.infinity), Money.zero);
      expect(Money.parse(1250.0).paise, 1250);
      expect(Money.parse(12.5).paise, 13, reason: 'rounds');
      expect(Money.parse(1 << 62).paise, Money.limit);
      expect(Money.parse(-(1 << 62)).paise, -Money.limit);
      expect(Money.parse(true), Money.zero);
      expect(Money.parse(<int>[1]), Money.zero);
    });

    test('sums stay inside the limit and never wrap', () {
      final big = Money(Money.limit);
      expect((big + big).paise, Money.limit);
      expect((-big - big).paise, -Money.limit);
    });

    test('basis points round half away from zero, in integers', () {
      expect(Money(1000).applyBp(1000).paise, 100); // 10%
      expect(Money(1005).applyBp(1000).paise, 101); // 100.5 -> 101
      expect(Money(1004).applyBp(1000).paise, 100);
      expect(Money(-1005).applyBp(1000).paise, -101, reason: 'mirror of the positive side');
      expect(Money(1005).applyBp(-1000).paise, -101);
      expect(Money(1).applyBp(5000).paise, 1); // 0.5 -> 1
      expect(Money(1).applyBp(4999).paise, 0);
      expect(Money(123456).applyBp(0), Money.zero);
      expect(Money(0).applyBp(500), Money.zero);
      expect(Money(777).applyBp(10000).paise, 777);
    });

    test('splitBp: the parts always add up to the whole', () {
      for (final p in [0, 1, 2, 99, 100, 101, 12345, 999999, -1, -777, -12345]) {
        for (final bp in [0, 1, 50, 250, 333, 500, 1000, 1234, 5000, 9999, 10000]) {
          final (part, rest) = Money(p).splitBp(bp);
          expect((part + rest).paise, p, reason: 'p=$p bp=$bp');
        }
      }
    });

    test('basis points on huge amounts (web-safe, no overflow)', () {
      final m = Money(Money.limit ~/ 2).applyBp(10000);
      expect(m.paise, Money.limit ~/ 2);
      expect(Money(Money.limit).applyBp(10000).paise, Money.limit);
      expect(Money(Money.limit).applyBp(20000).paise, Money.limit, reason: 'clamped');
    });
  });

  group('WalletEntry', () {
    WalletEntry e(String kind, int a, {String key = 'k'}) => WalletEntry(key: key, kind: kind, amount: Money(a));

    test('what makes a line unusable', () {
      expect(e(WalletKind.tripEarning, 100).problem, isNull);
      expect(e(WalletKind.tripEarning, 0).problem, 'zero');
      expect(e('mystery', 100).problem, 'kind');
      expect(e(WalletKind.tripEarning, 100, key: '').problem, 'key');
      expect(e(WalletKind.tripEarning, 100, key: 'x' * 201).problem, 'key');
      expect(e(WalletKind.tripEarning, WalletEntry.maxPaise + 1).problem, 'too_big');
      expect(e(WalletKind.commission, 50).problem, 'commission_sign');
      expect(e(WalletKind.commission, -50).problem, isNull);
      expect(e(WalletKind.payoutHold, -5).problem, 'negative');
      expect(e(WalletKind.adjustment, -5).problem, isNull, reason: 'a correction may be negative');
    });

    test('the existing ledger document maps over, its id is the key', () {
      final w = WalletEntry.fromLedger(const LedgerEntry(id: 'B1_trip_earning', driverId: 'd', bookingId: 'B1', type: LedgerType.tripEarning, amountPaise: 90000));
      expect(w.key, 'B1_trip_earning');
      expect(w.kind, WalletKind.tripEarning);
      expect(w.amount.paise, 90000);
      expect(w.problem, isNull);
    });
  });

  group('WalletBook', () {
    WalletEntry e(String kind, int a, String key) => WalletEntry(key: key, kind: kind, amount: Money(a));

    test('a trip, the commission and a payout move money between the boxes', () {
      final b = WalletBook();
      expect(b.tryAppend(e(WalletKind.pendingEarning, 100000, 'p1')), AppendResult.applied);
      expect(b.balance.pending.paise, 100000);
      expect(b.tryAppend(e(WalletKind.pendingSettle, 100000, 's1')), AppendResult.applied);
      expect(b.tryAppend(e(WalletKind.tripEarning, 100000, 't1')), AppendResult.applied);
      expect(b.tryAppend(e(WalletKind.commission, -10000, 'c1')), AppendResult.applied);
      expect(b.balance.available.paise, 90000);
      expect(b.tryAppend(e(WalletKind.payoutHold, 60000, 'h1')), AppendResult.applied);
      expect(b.balance.available.paise, 30000);
      expect(b.balance.held.paise, 60000);
      expect(b.tryAppend(e(WalletKind.payoutPaid, 60000, 'pd1')), AppendResult.applied);
      expect(b.balance.held.paise, 0);
      expect(b.balance.paidOut.paise, 60000);
      expect(b.balance.lifetime.paise, 90000);
      expect(b.balance.isSound, isTrue);
      expect(b.boxTotal, b.netInflow);
    });

    test('cannot ask for more than is available; nothing changes when refused', () {
      final b = WalletBook()..tryAppend(e(WalletKind.tripEarning, 5000, 't1'));
      final before = b.balance;
      expect(b.tryAppend(e(WalletKind.payoutHold, 5001, 'h1')), AppendResult.wouldGoNegative);
      expect(b.balance, before);
      expect(b.entries.length, 1);
      expect(b.tryAppend(e(WalletKind.payoutHold, 5000, 'h2')), AppendResult.applied);
      expect(b.balance.available, Money.zero);
      expect(b.tryAppend(e(WalletKind.commission, -1, 'c1')), AppendResult.wouldGoNegative, reason: 'not even one paisa below zero');
    });

    test('rejected payout is released; paid payout that comes back is reversed to available', () {
      final b = WalletBook()
        ..tryAppend(e(WalletKind.tripEarning, 10000, 't1'))
        ..tryAppend(e(WalletKind.payoutHold, 10000, 'h1'));
      expect(b.tryAppend(e(WalletKind.payoutRelease, 10000, 'r1')), AppendResult.applied);
      expect(b.balance.available.paise, 10000);
      expect(b.tryAppend(e(WalletKind.payoutRelease, 1, 'r2')), AppendResult.wouldGoNegative, reason: 'nothing is held any more');
      b.tryAppend(e(WalletKind.payoutHold, 10000, 'h2'));
      b.tryAppend(e(WalletKind.payoutPaid, 10000, 'pd2'));
      expect(b.tryAppend(e(WalletKind.payoutReversal, 10000, 'rv2')), AppendResult.applied);
      expect(b.balance.paidOut, Money.zero);
      expect(b.balance.available.paise, 10000);
      expect(b.tryAppend(e(WalletKind.payoutReversal, 1, 'rv3')), AppendResult.wouldGoNegative);
    });

    test('the same key counts once (retry, replay, double tap)', () {
      final b = WalletBook();
      expect(b.tryAppend(e(WalletKind.tripEarning, 700, 'same')), AppendResult.applied);
      expect(b.tryAppend(e(WalletKind.tripEarning, 700, 'same')), AppendResult.duplicate);
      expect(b.tryAppend(e(WalletKind.tripEarning, 9999, 'same')), AppendResult.duplicate, reason: 'the first one wins');
      expect(b.balance.available.paise, 700);
      expect(WalletBook.of([e(WalletKind.tripEarning, 700, 'z'), e(WalletKind.tripEarning, 700, 'z')]).balance.available.paise, 700);
    });

    test('invalid lines are refused or skipped, never crash', () {
      final b = WalletBook();
      expect(b.tryAppend(e(WalletKind.tripEarning, 0, 'a')), AppendResult.invalid);
      expect(b.tryAppend(e('nope', 5, 'b')), AppendResult.invalid);
      final loaded = WalletBook.of([e('nope', 5, 'x'), e(WalletKind.tripEarning, 0, 'y'), e(WalletKind.tripEarning, 50, 'z')]);
      expect(loaded.balance.available.paise, 50);
    });

    test('old stored data that goes below zero is kept and flagged, not hidden or thrown', () {
      final b = WalletBook.of([e(WalletKind.tripEarning, 1000, 't'), e(WalletKind.commission, -4000, 'c')]);
      expect(b.balance.available.paise, -3000);
      expect(b.balance.isSound, isFalse);
      expect(b.tryAppend(e(WalletKind.payoutHold, 100, 'h')), AppendResult.wouldGoNegative);
    });

    test('a settled pending box cannot go below zero either', () {
      final b = WalletBook();
      expect(b.tryAppend(e(WalletKind.pendingSettle, 1, 's')), AppendResult.wouldGoNegative);
    });
  });

  group('property tests (seeded random, thousands of lines)', () {
    const kinds = WalletKind.all;

    WalletEntry random(Random r, int i, {int maxAmount = 10000000}) {
      final kind = kinds[r.nextInt(kinds.length)];
      var a = r.nextBool() ? r.nextInt(maxAmount) + 1 : r.nextInt(2000) + 1;
      if (r.nextInt(25) == 0) a = 0;
      if (kind == WalletKind.commission || (kind == WalletKind.adjustment && r.nextBool())) a = -a;
      if (r.nextInt(30) == 0) a = -a; // sign mistakes
      // keys repeat now and then (duplicates)
      final key = r.nextInt(15) == 0 ? 'dup${r.nextInt(20)}' : 'k$i';
      return WalletEntry(key: key, kind: kind, amount: Money(a));
    }

    test('available (and every box) never goes below zero when lines go through tryAppend', () {
      for (var seed = 0; seed < 25; seed++) {
        final r = Random(seed);
        final b = WalletBook();
        for (var i = 0; i < 1500; i++) {
          b.tryAppend(random(r, i));
          final x = b.balance;
          expect(x.isSound, isTrue, reason: 'seed $seed line $i: $x');
        }
        expect(b.boxTotal, b.netInflow, reason: 'seed $seed: the boxes add up to the lines');
      }
    });

    test('rebuilding from the stored lines gives the same balance, in any order of the same lines', () {
      for (var seed = 100; seed < 115; seed++) {
        final r = Random(seed);
        final b = WalletBook();
        for (var i = 0; i < 1200; i++) {
          b.tryAppend(random(r, i, maxAmount: 90000000));
        }
        final applied = b.entries;
        final again = WalletBook.of(applied);
        expect(again.balance, b.balance, reason: 'seed $seed');
        final shuffled = [...applied]..shuffle(Random(seed));
        expect(WalletBook.of(shuffled).balance, b.balance, reason: 'seed $seed: sums do not depend on order');
        // Every line twice: duplicates change nothing.
        expect(WalletBook.of([...applied, ...applied]).balance, b.balance, reason: 'seed $seed');
      }
    });

    test('payouts only ever move money, they never create or destroy it', () {
      final r = Random(7);
      final b = WalletBook();
      for (var i = 0; i < 400; i++) {
        b.tryAppend(WalletEntry(key: 'e$i', kind: WalletKind.tripEarning, amount: Money(r.nextInt(500000) + 1)));
      }
      final total = b.balance.lifetime;
      for (var i = 0; i < 3000; i++) {
        final kind = const [WalletKind.payoutHold, WalletKind.payoutRelease, WalletKind.payoutPaid, WalletKind.payoutReversal][r.nextInt(4)];
        b.tryAppend(WalletEntry(key: 'p$i', kind: kind, amount: Money(r.nextInt(300000) + 1)));
        expect(b.balance.lifetime, total, reason: 'step $i');
        expect(b.balance.isSound, isTrue);
      }
    });

    test('huge and tiny amounts: a line over the maximum is refused, the maximum is accepted', () {
      final b = WalletBook();
      expect(b.tryAppend(WalletEntry(key: 'big', kind: WalletKind.tripEarning, amount: Money(WalletEntry.maxPaise))), AppendResult.applied);
      expect(b.tryAppend(WalletEntry(key: 'bigger', kind: WalletKind.tripEarning, amount: Money(WalletEntry.maxPaise + 1))), AppendResult.invalid);
      expect(b.tryAppend(WalletEntry(key: 'one', kind: WalletKind.tripEarning, amount: Money(1))), AppendResult.applied);
      expect(b.balance.available.paise, WalletEntry.maxPaise + 1);
    });

    test('basis points: rounding error is at most half a paisa and parts add up, for random amounts', () {
      final r = Random(42);
      for (var i = 0; i < 20000; i++) {
        final p = (r.nextInt(2) == 0 ? 1 : -1) * ((r.nextInt(1 << 30) << 10) + r.nextInt(1024));
        final bp = r.nextInt(10001);
        final (part, rest) = Money(p).splitBp(bp);
        expect((part + rest).paise, p);
        // exact rational check with integers: |part*10000 - p*bp| <= 5000
        final diff = (BigInt.from(part.paise) * BigInt.from(10000) - BigInt.from(p) * BigInt.from(bp)).abs();
        expect(diff <= BigInt.from(5000), isTrue, reason: 'p=$p bp=$bp');
      }
    });
  });
}
