import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// E14: the static landing page (hosting/index.html from tool/templates/hosting/index.html) is fast and plain,
/// and every rewrite and header that existed before it is still there (test/hosting_snapshot.json; routes may be
/// added later, never removed or changed).
void main() {
  final hosting = jsonDecode(File('firebase.json').readAsStringSync())['hosting'] as Map<String, dynamic>;
  final snapshot = jsonDecode(File('test/hosting_snapshot.json').readAsStringSync()) as Map<String, dynamic>;
  final html = File('hosting/index.html').readAsStringSync();
  final css = File('hosting/assets/landing.css').readAsStringSync();

  test('every earlier rewrite is kept with the same destination', () {
    final now = {for (final r in hosting['rewrites'] as List) r['source']: jsonEncode(r)};
    for (final r in snapshot['rewrites'] as List) {
      expect(now[r['source']], jsonEncode(r), reason: '${r['source']} changed or was removed');
    }
  });

  test('every earlier header block is kept unchanged', () {
    final now = {for (final h in hosting['headers'] as List) h['source']: jsonEncode(h)};
    for (final h in snapshot['headers'] as List) {
      expect(now[h['source']], jsonEncode(h), reason: '${h['source']} headers changed or were removed');
    }
  });

  test('the page is small: html and css together under 12 KB, no images to download', () {
    expect(html.length + css.length, lessThan(12 * 1024));
    expect(html.contains('<img'), isFalse);
    expect(RegExp(r'url\(').hasMatch(css), isFalse);
  });

  test('nothing is loaded from another host (the content policy allows only our own files)', () {
    expect(RegExp(r'''(src|href)=["']https?://''').hasMatch(html), isFalse);
    expect(RegExp(r'https?://').hasMatch(css), isFalse);
    expect(html, contains('href="/assets/landing.css"'));
  });

  test('every link goes to a real route', () {
    final routes = {'/', for (final r in hosting['rewrites'] as List) r['source'] as String};
    for (final m in RegExp(r'href="(/[^"]*)"').allMatches(html)) {
      final href = m.group(1)!;
      if (href.startsWith('/assets/')) continue;
      expect(routes, contains(href), reason: href);
    }
  });

  test('the name comes from AppInfo, the page is generated from its template, and it is accessible', () {
    final template = File('tool/templates/hosting/index.html').readAsStringSync();
    expect(template, contains('{{APP_NAME}}'));
    expect(template.contains('Load 20'), isFalse, reason: 'the name must come from AppInfo');
    expect(html.contains('{{'), isFalse, reason: 'run dart run tool/apply_app_info.dart');
    expect(html, contains('<html lang="en">'));
    expect(html, contains('name="viewport"'));
    expect(RegExp('<h1>').allMatches(html).length, 1);
    expect(html, contains('aria-hidden="true"'), reason: 'the drawn mark is decoration; the name is text next to it');
  });

  test('light, dark and reduced motion are handled in the stylesheet', () {
    expect(css, contains('prefers-color-scheme:dark'));
    expect(css, contains('prefers-reduced-motion:reduce'));
  });

  test('no promise the app cannot keep', () {
    final t = html.toLowerCase();
    for (final bad in ['guarantee', 'insur', 'escrow', 'loan', 'cheapest', 'best price', 'no.1', 'number one']) {
      expect(t.contains(bad), isFalse, reason: bad);
    }
  });
}
