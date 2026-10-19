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
    test('$route: a content policy that allows only our own script and Firestore, and is never cached or indexed', () {
      final h = headers[route]!;
      final csp = h['Content-Security-Policy']!;
      expect(csp, contains("default-src 'none'"));
      expect(csp, contains('connect-src https://firestore.googleapis.com'));
      expect(csp, contains("frame-ancestors 'none'"));
      expect(csp, isNot(contains('*')));
      expect(h['Cache-Control'], 'no-store');
      expect(h['X-Robots-Tag'], contains('noindex'));
    });
  }

  // H12: no page needs inline script or style any more, so the policy never says unsafe-inline.
  test('no content policy anywhere allows inline script or style', () {
    for (final e in headers.entries) {
      final csp = e.value['Content-Security-Policy'];
      if (csp == null) continue;
      expect(csp, isNot(contains('unsafe-inline')), reason: e.key);
      expect(csp, isNot(contains('unsafe-eval')), reason: e.key);
      expect(csp, contains("script-src 'self'"), reason: e.key);
    }
  });

  test('the shared load page and every plain page carry a policy too, and the load page is never cached or indexed', () {
    expect(headers['/load/**']!['Content-Security-Policy'], isNot(contains('connect-src')));
    expect(headers['/load/**']!['Cache-Control'], 'no-store');
    expect(headers['/load/**']!['X-Robots-Tag'], contains('noindex'));
    for (final p in ['/', '/privacy', '/terms', '/refund', '/driver-agreement', '/transporter-agreement', '/delete-account']) {
      expect(headers[p]?['Content-Security-Policy'], contains("default-src 'none'"), reason: p);
    }
  });

  test('every html page loads its script and style from /assets and holds none inline', () {
    for (final f in Directory('hosting').listSync().whereType<File>().where((f) => f.path.endsWith('.html'))) {
      final html = f.readAsStringSync();
      expect(RegExp(r'<script(?![^>]*\bsrc=)').hasMatch(html), isFalse, reason: '${f.path} has an inline script');
      expect(html.contains('<style'), isFalse, reason: '${f.path} has an inline style');
      expect(RegExp(r'\son[a-z]+\s*=').hasMatch(html), isFalse, reason: '${f.path} has an inline handler');
      expect(RegExp(r'\sstyle\s*=').hasMatch(html), isFalse, reason: '${f.path} has a style attribute');
    }
  });

  test('the old rewrites still point where they did', () {
    final rewrites = {for (final r in (hosting['rewrites'] as List)) r['source'] as String: r['destination'] as String};
    expect(rewrites['/trip/**'], '/trip.html');
    expect(rewrites['/lr/**'], '/lr.html');
    expect(rewrites['/load/**'], '/load.html');
    expect(rewrites['/privacy'], '/privacy.html');
    expect(rewrites['/terms'], '/terms.html');
    expect(rewrites['/delete-account'], '/delete-account.html');
  });

  test('security.txt is published and holds a contact', () {
    final t = File('hosting/.well-known/security.txt').readAsStringSync();
    expect(t, contains('Contact:'));
    expect(t, contains('Expires:'));
    final ignore = (hosting['ignore'] as List).cast<String>();
    expect(ignore.any((i) => i == '**/.*'), isFalse, reason: 'the dot-folder rule would hide .well-known');
  });

  test('the script of each token page talks to no host other than Firestore', () {
    for (final page in ['hosting/lr.html', 'hosting/trip.html', 'hosting/assets/lr.js', 'hosting/assets/trip.js']) {
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
