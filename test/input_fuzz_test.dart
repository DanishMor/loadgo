import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/comm/contact_filter.dart';
import 'package:transport_app/core/enterprise/validators.dart';
import 'package:transport_app/core/identity/kyc_validators.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/search/global_search.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/core/widgets/common.dart';

/// MASTER-5 Phase B round 1: whatever a person types (or pastes) must not
/// throw and must not take long. Random text of every kind goes through the
/// parsers, validators and the chat filter.
void main() {
  final rnd = Random(20261008);
  const pools = [
    '0123456789',
    '0123456789 -.+()',
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ',
    'अआइईउऊएऐओऔकखगघचछजझटठडढणतथदधनपफबभमयरलवशषसह०१२३४५६७८९',
    'ابپتٹثجچحخدڈذرڑزژسشصضطظعغفقکگلمنںوہھیے۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩',
    '​‍﻿\t\n\r',
    r'''=+-@"',;<>{}[]\/|%$#!~`^*_''',
    '😀🚚₹①②③⑩❶',
  ];

  String junk(int len) {
    final pool = pools[rnd.nextInt(pools.length)] + pools[rnd.nextInt(pools.length)];
    final runes = pool.runes.toList();
    return String.fromCharCodes([for (var i = 0; i < len; i++) runes[rnd.nextInt(runes.length)]]);
  }

  final parsers = <String, Object? Function(String)>{
    'paiseFromRupees': TripAccount.paiseFromRupees,
    'isValidVehicleNumber': isValidVehicleNumber,
    'isValidIndianMobile': isValidIndianMobile,
    'isValidPincode': isValidPincode,
    'isValidPan': isValidPan,
    'isValidDlNumber': isValidDlNumber,
    'isValidAadhaarLast4': isValidAadhaarLast4,
    'isValidGstin': isValidGstin,
    'isValidGstinFormat': isValidGstinFormat,
    'isValidContainerNumber': isValidContainerNumber,
    'isValidSealNumber': isValidSealNumber,
    'normaliseCode': Promo.normaliseCode,
    'ContactFilter.check': ContactFilter.check,
  };

  for (final e in parsers.entries) {
    test('${e.key}: 600 random inputs of 0 to 400 characters never throw', () {
      for (var i = 0; i < 600; i++) {
        final s = junk(rnd.nextInt(400));
        expect(() => e.value(s), returnsNormally, reason: 'input: ${s.runes.take(60).map((r) => r.toRadixString(16)).join(' ')}');
      }
    });
  }

  test('long adversarial strings are checked fast (no catastrophic backtracking)', () {
    final long = [
      '9' * 20000,
      '9 ' * 10000,
      'a1' * 10000,
      ('९८७६५ ' * 3000),
      ' ' * 20000,
      '${'0' * 5000}x',
      '${'x' * 5000}@${'y' * 5000}',
      ('call ' * 4000),
      '+91' * 6000,
    ];
    final sw = Stopwatch()..start();
    for (final s in long) {
      ContactFilter.check(s);
      TripAccount.paiseFromRupees(s);
      isValidIndianMobile(s);
      isValidGstin(s);
      isValidVehicleNumber(s);
    }
    expect(sw.elapsedMilliseconds, lessThan(3000), reason: 'took ${sw.elapsedMilliseconds} ms');
  });

  test('money text: formatPaise never throws and keeps the sign and the paise; parsing and printing agree', () {
    for (var i = 0; i < 2000; i++) {
      final paise = (rnd.nextDouble() * 2 - 1).sign.toInt() * rnd.nextInt(1 << 31) * (rnd.nextBool() ? 1 : 1000);
      final s = formatPaise(paise);
      expect(s.contains('-'), paise < 0, reason: '$paise -> $s');
      expect(s, startsWith(paise < 0 ? '-₹' : '₹'));
    }
    for (var p = 0; p < 100000; p += 137) {
      final text = '${p ~/ 100}.${(p % 100).toString().padLeft(2, '0')}';
      expect(TripAccount.paiseFromRupees(text), p, reason: text);
    }
    expect(TripAccount.paiseFromRupees('1,00,000.5'), 10000050);
    expect(TripAccount.paiseFromRupees('1e5'), isNull);
    expect(TripAccount.paiseFromRupees('-5'), isNull);
    expect(TripAccount.paiseFromRupees('1000000000'), isNull, reason: 'over the limit');
  });

  test('global search copes with any query', () {
    final index = GlobalSearch(const []);
    for (var i = 0; i < 300; i++) {
      expect(() => index.search(junk(rnd.nextInt(80))), returnsNormally);
    }
  });
}
