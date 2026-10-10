import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// P4: signing material can never be committed by accident. Asks git itself
/// whether a path is ignored (no file needs to exist).
void main() {
  Future<bool> ignored(String path) async {
    final r = await Process.run('git', ['check-ignore', '-q', '--no-index', path]);
    return r.exitCode == 0;
  }

  for (final path in [
    'upload.jks',
    'android/app/upload.jks',
    'release.keystore',
    'android/app/release.keystore',
    'nested/dir/anything.jks',
    'android/key.properties',
  ]) {
    test('git ignores $path', () async {
      expect(await ignored(path), isTrue, reason: '$path must be git-ignored');
    });
  }

  test('no keystore or key.properties is tracked', () async {
    final r = await Process.run('git', ['ls-files']);
    final tracked = (r.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    final bad = tracked.where((f) => f.endsWith('.jks') || f.endsWith('.keystore') || f.endsWith('key.properties'));
    expect(bad, isEmpty);
  });

  test('SIGNING.md covers the steps and holds no password value', () {
    final raw = File('docs/SIGNING.md').readAsStringSync();
    final doc = raw.toLowerCase();
    for (final w in ['keytool', 'play app signing', 'key.properties', 'backup', 'repo ke bahar']) {
      expect(doc.contains(w), isTrue, reason: w);
    }
    // A password line must hold a <placeholder>, never a value.
    for (final m in RegExp(r'^(storePassword|keyPassword)=(.*)$', multiLine: true).allMatches(raw)) {
      expect(m.group(2)!.trim().startsWith('<'), isTrue, reason: m.group(0));
    }
  });
}
