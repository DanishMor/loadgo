import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-5 gap (security headers): the public pages carry a token in their
/// address, so they get headers that keep it from leaking or being framed.
void main() {
  final hosting = jsonDecode(File('firebase.json').readAsStringSync())['hosting'] as Map;
  final headers = {
    for (final h in (hosting['headers'] as List)) h['source'] as String: {for (final e in (h['headers'] as List)) e['key'] as String: e['value'] as String},
  };

  test('every page: no sniffing, no framing, no referrer, HTTPS only, no sensors', () {
    final all = headers['**']!;
    expect(all['X-Content-Type-Options'], 'nosniff');
    expect(all['X-Frame-Options'], 'DENY');
    expect(all['Referrer-Policy'], 'no-referrer');
    expect(all['Strict-Transport-Security'], contains('max-age=31536000'));
    expect(all['Permissions-Policy'], contains('geolocation=()'));
  });

  for (final route in ['/lr/**', '/trip/**']) {
    test('$route: a content policy that allows only the inline page script and Firestore, and is never cached', () {
      final h = headers[route]!;
      final csp = h['Content-Security-Policy']!;
      expect(csp, contains("default-src 'none'"));
      expect(csp, contains('connect-src https://firestore.googleapis.com'));
      expect(csp, contains("frame-ancestors 'none'"));
      expect(csp, isNot(contains('*')));
      expect(h['Cache-Control'], 'no-store');
    });
  }

  test('the script of each token page talks to no host other than Firestore', () {
    for (final page in ['hosting/lr.html', 'hosting/trip.html']) {
      final hosts = {for (final m in RegExp(r'https?://([a-z0-9.-]+)').allMatches(File(page).readAsStringSync())) m.group(1)!};
      expect(hosts.difference({'firestore.googleapis.com'}), isEmpty, reason: page);
    }
  });

  test('the Android app is not copied to a cloud backup and speaks HTTPS only (saved LR copies live on the phone)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
  });
}
