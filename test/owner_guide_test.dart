import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/admin/staff_roles.dart';

/// MASTER-6 Task 48: the owner guide covers every admin screen and the four playbooks.
void main() {
  final guide = File('docs/OWNER_GUIDE.md').readAsStringSync();
  final where = File('docs/WHERE_IS_WHAT.md').readAsStringSync();

  test('every admin area has a bold name in the guide (names come from the where-is-what test list)', () {
    final test = File('test/where_is_what_test.dart').readAsStringSync();
    final names = RegExp(r"'(\w+)': '([^']+)'").allMatches(test).where((m) => staffAreas.containsKey(m.group(1))).map((m) => m.group(2)!).toList();
    expect(names.length, staffAreas.length);
    for (final n in names) {
      expect(guide.contains('**$n**'), isTrue, reason: '$n is not explained in docs/OWNER_GUIDE.md');
    }
    expect(where.isNotEmpty, isTrue);
  });

  test('the playbooks and the daily checklist are there', () {
    for (final h in ['### SOS aaya', '### Accident ya breakdown', '### Fraud ka shak', '### Dispute', '## 2. Roz ki checklist', '## 1. Pilot kaise chalayein']) {
      expect(guide.contains(h), isTrue, reason: h);
    }
  });

  test('the guide says plainly that money is only recorded and the legal texts are drafts', () {
    expect(guide.contains('record rakhta hai'), isTrue);
    expect(guide.contains('DRAFT'), isTrue);
  });
}
