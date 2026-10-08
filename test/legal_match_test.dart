import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-5 Task 8: the Privacy Policy and Terms (docs and public pages) name
/// every feature that touches personal data or user duties.
void main() {
  final privacy = ['docs/PRIVACY_POLICY.md', 'hosting/privacy.html'];
  final terms = ['docs/TERMS.md', 'hosting/terms.html'];

  void has(List<String> files, List<String> words) {
    for (final f in files) {
      final t = File(f).readAsStringSync().toLowerCase();
      for (final w in words) {
        expect(t, contains(w.toLowerCase()), reason: '$f should mention "$w"');
      }
    }
  }

  test('privacy names calls, chat records, strikes, share links, bilty, inspection, audit, clean-up', () {
    has(privacy, ['microphone', 'violation', 'share', 'bilty', 'inspection', 'audit log', 'deleted automatically', 'delete your account']);
  });

  test('terms name the chat rules, trip and bilty links, inspection, the hourly limit', () {
    has(terms, ['phone numbers', 'strikes', 'inspection', 'limit', 'bilty']);
  });
}
