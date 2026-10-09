import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-6 Task 44: the listing drafts fit the store limits.
void main() {
  final doc = File('docs/PLAY_LISTING.md').readAsStringSync();

  String between(String a, String b) => doc.substring(doc.indexOf(a) + a.length, doc.indexOf(b)).trim();

  test('short descriptions are 80 characters or fewer in English, Hindi and Hinglish', () {
    for (final k in ['SHORT_EN', 'SHORT_HI', 'SHORT_HG']) {
      final line = doc.split('\n').firstWhere((l) => l.contains('$k: '));
      final text = line.substring(line.indexOf('$k: ') + k.length + 2).trim();
      expect(text.runes.length, lessThanOrEqualTo(80), reason: '$k: $text');
      expect(text, isNotEmpty);
    }
  });

  test('full descriptions are under 4000 characters and make no payment or safety promise the app cannot keep', () {
    for (final k in ['EN', 'HI', 'HG']) {
      final t = between('FULL_${k}_START', 'FULL_${k}_END');
      expect(t.runes.length, lessThan(4000), reason: k);
      expect(t.runes.length, greaterThan(500), reason: k);
    }
    final lower = doc.toLowerCase();
    for (final bad in ['guaranteed delivery', 'insured', 'insurance included', '100% safe']) {
      expect(lower.contains(bad), isFalse, reason: bad);
    }
    expect(doc.contains('DRAFT'), isTrue);
  });

  test('the checklist points to the listing, the release doc and the legal drafts', () {
    final c = File('docs/PLAY_STORE_CHECKLIST.md').readAsStringSync();
    expect(c.contains('PLAY_LISTING.md'), isTrue);
    expect(c.contains('ANDROID_RELEASE.md'), isTrue);
  });
}
