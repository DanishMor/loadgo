import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F46: every path named in the Part 2 map of WHERE_IS_WHAT.md exists.
void main() {
  test('the Part 2 section points to real files', () {
    final doc = File('docs/WHERE_IS_WHAT.md').readAsStringSync();
    final part = doc.substring(doc.indexOf('## Part 2: server'));
    final paths = RegExp(r'`((?:lib|docs|functions|firestore_rules_test|android)/[A-Za-z0-9_./-]+|storage\.rules|firestore\.rules|firebase\.integration\.json)`').allMatches(part).map((m) => m.group(1)!).toSet();
    expect(paths.length, greaterThan(30));
    for (final p in paths) {
      expect(FileSystemEntity.typeSync(p) != FileSystemEntityType.notFound, isTrue, reason: p);
    }
  });
}
