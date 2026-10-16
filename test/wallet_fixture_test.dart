import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/money/wallet_book.dart';

/// F23: functions/test/fixtures/wallet_cases.json is what the Dart WalletBook works out.
/// If this fails, the Dart book changed: regenerate the file
/// (flutter test tool/make_wallet_fixture_test.dart) and update functions/src/wallet.js.
void main() {
  final fixture = jsonDecode(File('functions/test/fixtures/wallet_cases.json').readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  test('the Dart book still gives every answer in the fixture', () {
    expect(cases.length, greaterThanOrEqualTo(400));
    final wrong = <String>[];
    for (var n = 0; n < cases.length; n++) {
      final c = cases[n];
      final ledger = (c['ledger'] as List).cast<Map<String, dynamic>>();
      final payouts = (c['payouts'] as List).cast<Map<String, dynamic>>();
      final b = WalletBook.fromSources(
        ledger: [for (var i = 0; i < ledger.length; i++) LedgerEntry(id: 'l${n}_$i', driverId: 'd', bookingId: 'b', type: ledger[i]['type'] as String, amountPaise: ledger[i]['amountPaise'] as int)],
        payouts: [for (var i = 0; i < payouts.length; i++) Payout(id: 'p${n}_$i', driverId: 'd', amountPaise: payouts[i]['amountPaise'] as int, status: payouts[i]['status'] as String)],
      ).balance;
      final e = c['expected'] as Map<String, dynamic>;
      if (b.available.paise != e['available'] || b.held.paise != e['held'] || b.paidOut.paise != e['paidOut']) {
        wrong.add('case $n: ${b.available.paise}/${b.held.paise}/${b.paidOut.paise} vs $e');
      }
    }
    expect(wrong, isEmpty);
  });

  test('the fixture has books of every shape', () {
    bool any(bool Function(Map<String, dynamic>) f) => cases.any(f);
    expect(any((c) => (c['expected'] as Map)['available'] < 0), isTrue, reason: 'an overdrawn book');
    expect(any((c) => (c['payouts'] as List).isEmpty), isTrue);
    expect(any((c) => (c['ledger'] as List).isEmpty), isTrue);
    expect(any((c) => (c['expected'] as Map)['held'] > 0), isTrue);
    expect(any((c) => (c['expected'] as Map)['paidOut'] > 0), isTrue);
  });
}
