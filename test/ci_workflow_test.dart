import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Z20: the CI file keeps least permissions and pinned actions, and runs analyze, batched tests, functions and rules tests.
void main() {
  final ci = File('.github/workflows/ci.yml').readAsStringSync();

  test('every action is pinned to a full commit id and the token can only read', () {
    final uses = RegExp(r'uses:\s*(\S+)').allMatches(ci).map((m) => m.group(1)!).toList();
    expect(uses, isNotEmpty);
    for (final u in uses) {
      expect(RegExp(r'@[0-9a-f]{40}$').hasMatch(u), isTrue, reason: '$u is not pinned');
    }
    expect(ci, contains('permissions:\n  contents: read'.replaceAll('\n', ci.contains('\r\n') ? '\r\n' : '\n')));
  });

  test('analyze, batched flutter tests, index check, functions and rules tests are all there', () {
    for (final needle in ['flutter analyze', 'split -l 30', '--concurrency=1', 'tool/check_indexes.js', 'working-directory: functions', 'working-directory: firestore_rules_test']) {
      expect(ci, contains(needle));
    }
  });
}
