import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-5 Phase B round 2: docs/TEST_PLAN.md says which test files cover
/// which flow. A file named there must exist, so the map cannot rot.
void main() {
  final plan = File('docs/TEST_PLAN.md').readAsStringSync();
  final names = {for (final m in RegExp(r'`((?:test|firestore_rules_test)/[A-Za-z0-9_/]+\.(?:dart|mjs))`').allMatches(plan)) m.group(1)!};

  test('the plan has an automated-coverage table', () {
    expect(plan, contains('## Automated coverage'));
    expect(names.length, greaterThan(40));
  });

  test('every test file named in the plan exists', () {
    final missing = [for (final n in names) if (!File(n).existsSync()) n];
    expect(missing, isEmpty);
  });

  test('every role section of the plan has a row in the table', () {
    for (final area in ['| Customer |', '| Driver |', '| Bilty and inspection |', '| Transporter |', '| Business account |', '| Admin |', '| Rules |']) {
      expect(plan, contains(area));
    }
  });
}
