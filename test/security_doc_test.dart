import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-6 Task 47: the security review names every collection the rules
/// know about, so a new collection cannot be added without being reviewed.
void main() {
  final rules = File('firestore.rules').readAsStringSync();
  final review = File('docs/SECURITY_REVIEW.md').readAsStringSync();

  test('every collection added in MASTER-6 is in the review table', () {
    const m6 = ['invite_codes', 'invite_redemptions', 'pilot_whitelist', 'waitlist', 'dispatch_suggestions', 'trip_surveys', 'payment_nudges', 'config_history', 'strike_appeals', 'inspection_log'];
    for (final c in m6) {
      expect(rules.contains('match /$c/'), isTrue, reason: '$c is not in firestore.rules any more');
      expect(review.contains('`$c`') || review.contains('/$c`'), isTrue, reason: '$c is missing from docs/SECURITY_REVIEW.md');
    }
  });

  test('the review has a threat model, a client-only list and a pentest checklist', () {
    for (final h in ['Who could attack', 'Checks that run only in the app', 'Pentest checklist for the owner']) {
      expect(review.contains(h), isTrue, reason: h);
    }
  });

  test('no secret-looking values are committed in lib, docs or android', () {
    final bad = <String>[];
    final re = RegExp(r'(?:password|secret|private_key)\s*[:=]\s*["\x27][^"\x27\s]{8,}', caseSensitive: false);
    for (final dir in ['lib', 'docs', 'android/app']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!RegExp(r'\.(dart|md|kts|xml|properties|json)$').hasMatch(f.path)) continue;
        if (f.path.endsWith('google-services.json')) continue;
        if (re.hasMatch(f.readAsStringSync())) bad.add(f.path);
      }
    }
    expect(bad, isEmpty);
  });
}
