import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-6 Task 45: every legal text is marked as a draft for a lawyer, has
/// a public page, and says only what the app does.
void main() {
  const pages = {
    'docs/PRIVACY_POLICY.md': 'hosting/privacy.html',
    'docs/TERMS.md': 'hosting/terms.html',
    'docs/REFUND_POLICY.md': 'hosting/refund.html',
    'docs/DRIVER_AGREEMENT.md': 'hosting/driver-agreement.html',
    'docs/TRANSPORTER_AGREEMENT.md': 'hosting/transporter-agreement.html',
  };

  test('each legal text and its page say DRAFT and that a lawyer must review it', () {
    pages.forEach((doc, page) {
      for (final f in [doc, page]) {
        final t = File(f).readAsStringSync().toLowerCase();
        expect(t.contains('draft'), isTrue, reason: '$f has no DRAFT mark');
        expect(t.contains('lawyer'), isTrue, reason: '$f has no lawyer note');
      }
    });
    for (final f in ['docs/REFUND_POLICY.md', 'docs/DRIVER_AGREEMENT.md', 'docs/TRANSPORTER_AGREEMENT.md']) {
      expect(File(f).readAsStringSync().contains('vakeel se review zaroori'), isTrue, reason: f);
    }
  });

  test('every page is served by a hosting rewrite and linked from the home page', () {
    final rewrites = (jsonDecode(File('firebase.json').readAsStringSync())['hosting']['rewrites'] as List).map((r) => r['source']).toSet();
    final home = File('hosting/index.html').readAsStringSync();
    for (final page in pages.values) {
      final slug = page.split('/').last.replaceAll('.html', '');
      expect(rewrites, contains('/$slug'), reason: slug);
      expect(home.contains('href="/$slug"'), isTrue, reason: '$slug is not linked from the home page');
    }
  });

  test('the texts promise no payment handling, insurance or income', () {
    for (final doc in pages.keys) {
      final t = File(doc).readAsStringSync().toLowerCase();
      for (final bad in ['we will refund', 'we guarantee', 'guaranteed income', 'we insure', 'escrow']) {
        expect(t.contains(bad), isFalse, reason: '$doc says "$bad"');
      }
    }
    final refund = File('docs/REFUND_POLICY.md').readAsStringSync();
    expect(refund.contains('does not hold or move money'), isTrue);
  });
}
