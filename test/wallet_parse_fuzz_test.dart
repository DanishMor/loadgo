import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/money/money.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';

/// F10: every parser that feeds a money screen survives any document.
void main() {
  final weird = <Object?>[
    null,
    '',
    'text',
    '12',
    0,
    -1,
    1,
    123456789012345,
    1 << 62,
    -(1 << 62),
    1.5,
    -2.5,
    double.nan,
    double.infinity,
    double.negativeInfinity,
    true,
    false,
    <Object?>[],
    <Object?>[1, 'a'],
    <String, Object?>{},
    <String, Object?>{'a': 1},
    Timestamp.fromMillisecondsSinceEpoch(0),
    Timestamp.fromMillisecondsSinceEpoch(4102444800000),
    DateTime(2026),
  ];

  Map<String, Object?> randomDoc(Random r, List<String> keys) => {
        for (final k in keys)
          if (r.nextInt(5) != 0) k: weird[r.nextInt(weird.length)],
      };

  test('LedgerEntry.fromDoc: thousands of damaged documents, no exception, sane numbers', () async {
    final db = FakeFirebaseFirestore();
    final r = Random(1);
    for (var i = 0; i < 400; i++) {
      await db.collection('ledger').doc('d$i').set(randomDoc(r, ['driverId', 'bookingId', 'type', 'amountPaise', 'createdAt']));
    }
    final snaps = (await db.collection('ledger').get()).docs;
    for (final s in snaps) {
      final e = LedgerEntry.fromDoc(s);
      expect(e.amountPaise.abs(), lessThanOrEqualTo(Money.limit));
      expect(e.id, s.id);
    }
    // And the totals over any mix.
    final sum = WalletSummary.of(snaps.map(LedgerEntry.fromDoc));
    expect(sum.net.abs(), lessThan(1 << 62));
  });

  test('CreditLine.fromDoc and TripAccount.fromMap and Payout.fromDoc: the same', () {
    final r = Random(2);
    for (var i = 0; i < 3000; i++) {
      final c = CreditLine.fromDoc('c$i', randomDoc(r, ['amountPaise', 'kind', 'loadId', 'note', 'createdAt']));
      expect(c.amountPaise.abs(), lessThanOrEqualTo(Money.limit));
      final t = TripAccount.fromMap('t$i', randomDoc(r, ['partyId', 'partyName', 'revenuePaise', 'driverPayPaise', 'otherCostPaise', 'receivedPaise', 'createdAt', 'updatedAt']));
      expect(t.revenuePaise.abs(), lessThanOrEqualTo(Money.limit));
      expect(() => t.marginPaise, returnsNormally);
      expect(() => t.dueFromPartyPaise, returnsNormally);
      final p = Payout.fromDoc('p$i', randomDoc(r, ['driverId', 'amountPaise', 'status', 'createdAt', 'approvedBy', 'paidBy', 'reference']));
      expect(Payout.all.contains(p.status), isTrue);
      expect(p.amountPaise.abs(), lessThanOrEqualTo(Money.limit));
    }
  });

  test('Money.parse: every odd value is a number within the limit', () {
    for (final v in weird) {
      final m = Money.parse(v);
      expect(m.paise.abs(), lessThanOrEqualTo(Money.limit), reason: '$v');
    }
  });

  test('old documents with only some fields still read', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('ledger').doc('x').set({'amountPaise': 500});
    expect(LedgerEntry.fromDoc(await db.collection('ledger').doc('x').get()).amountPaise, 500);
    expect(CreditLine.fromDoc('c', const {}).amountPaise, 0);
    expect(TripAccount.fromMap('t', const {}).revenuePaise, 0);
    expect(Payout.fromDoc('p', const {}).status, Payout.requested);
  });
}
