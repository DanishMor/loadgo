import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Z15: key files can never be committed, and tool/make_keystore.ps1 never prints or stores a password on the way.
void main() {
  test('.gitignore keeps keystores and key.properties out of git', () {
    final ignore = File('.gitignore').readAsLinesSync().map((l) => l.trim()).toSet();
    expect(ignore, containsAll(['android/key.properties', '*.jks', '*.keystore']));
  });

  test('git itself ignores a test key file', () {
    for (final f in ['android/key.properties', 'android/app/upload.jks', 'x/release.keystore']) {
      final r = Process.runSync('git', ['check-ignore', '-q', f]);
      expect(r.exitCode, 0, reason: '$f must be git-ignored');
    }
  });

  test('make_keystore.ps1: hidden input, keystore outside the repo, no password printed or put on the command line', () {
    final s = File('tool/make_keystore.ps1').readAsStringSync();
    expect(s, contains('-AsSecureString'));
    expect(s, contains('load20-keys'));
    expect(s, contains('-storepass:env'));
    expect(s, isNot(contains(r'-storepass $')));
    expect(s, isNot(contains(r'-keypass $')));
    expect(RegExp(r'Write-(Host|Output)[^\n]*\$(store|key|p1|p2|k1)\b').hasMatch(s), isFalse);
    expect(s, contains('Overwrite nahi'));
    expect(File('docs/SIGNING.md').readAsStringSync(), contains('make_keystore.ps1'));
  });
}
