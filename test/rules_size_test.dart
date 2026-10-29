import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// E2: firestore.rules must stay well below the believed 256 KB limit (UNVERIFIED).
/// The annotated copy with all comments is docs/firestore.rules.annotated.txt.
void main() {
  test('firestore.rules is under the 235 KB budget', () {
    final size = File('firestore.rules').lengthSync();
    expect(size, lessThan(235 * 1024), reason: 'firestore.rules is $size bytes; see docs/RULES_BUDGET.md');
  });
  test('storage.rules is small', () {
    expect(File('storage.rules').lengthSync(), lessThan(32 * 1024));
  });
}
