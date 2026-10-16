import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F43: the known-issues file stays in step with the blocked list and the switches that are OFF.
void main() {
  final known = File('docs/KNOWN_ISSUES.md').readAsStringSync();

  test('it names what is still manual or paid', () {
    for (final w in ['secureScreens', 'appLock', 'walletStepUp', 'Cloud Functions', 'Razorpay', 'KYC', 'MSG91', 'App Check', 'TRANSLATION_REVIEW.csv', 'LOGO_BRIEF.md']) {
      expect(known, contains(w), reason: w);
    }
  });

  test('every file it points to exists', () {
    for (final m in RegExp(r'`((?:docs|lib|functions)/[A-Za-z0-9_./-]+\.[a-z]+)`').allMatches(known)) {
      expect(File(m.group(1)!).existsSync(), isTrue, reason: m.group(1));
    }
  });

  test('the function count matches the deployed index', () {
    final n = RegExp(r'^exports\.\w+', multiLine: true).allMatches(File('functions/index.js').readAsStringSync()).length;
    expect(known, contains('Cloud Functions ($n functions)'));
  });
}
