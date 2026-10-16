import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F40: the privacy text, the data-safety answers and the release checklist agree with each other.
void main() {
  String read(String f) => File(f).readAsStringSync().toLowerCase();

  test('privacy (md and public page) name photos, push token, earnings records and login safety', () {
    for (final f in ['docs/PRIVACY_POLICY.md', 'hosting/privacy.html']) {
      final t = read(f);
      for (final w in ['photos', 'push notifications', 'earnings records', 'login safety', 'razorpay', 'never makes a public link']) {
        expect(t, contains(w), reason: '$f: $w');
      }
    }
  });

  test('the data safety notes cover photos, device id for push, financial info and the payments declaration', () {
    final t = read('docs/PLAY_STORE_CHECKLIST.md');
    for (final w in ['data safety additions for part 2', 'photos and videos', 'push token', 'financial info', 'paymentgateway', 'merged manifest']) {
      expect(t, contains(w), reason: w);
    }
  });

  test('the manifest has no permission that the checklist does not explain', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final checklist = File('docs/PLAY_STORE_CHECKLIST.md').readAsStringSync();
    for (final m in RegExp(r'uses-permission android:name="android\.permission\.([A-Z_]+)"').allMatches(manifest)) {
      final name = m.group(1)!;
      expect(checklist.contains(name) || (name == 'ACCESS_COARSE_LOCATION' && checklist.contains('COARSE')), isTrue, reason: name);
    }
  });

  test('the release checklist links to files that exist', () {
    final t = File('docs/RELEASE_CANDIDATE.md').readAsStringSync();
    final files = RegExp(r'`(docs/[A-Z_]+\.(?:md|csv))`').allMatches(t).map((m) => m.group(1)!).toSet();
    expect(files.length, greaterThan(8));
    for (final f in files) {
      expect(File(f).existsSync(), isTrue, reason: f);
    }
  });
}
