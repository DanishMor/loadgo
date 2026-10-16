import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/comm/contact_filter.dart';
import 'package:transport_app/core/comm/chat_strikes.dart';

/// F17: functions/test/fixtures/contact_cases.json is what the Dart filter answers.
/// If this fails, the Dart filter changed: regenerate the file
/// (flutter test tool/make_contact_fixture_test.dart) and update functions/src/contactFilter.js.
void main() {
  final fixture = jsonDecode(File('functions/test/fixtures/contact_cases.json').readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  test('the fixture is big and has every kind', () {
    expect(cases.length, greaterThan(300));
    expect({for (final c in cases) c['kind']}, containsAll(['phone', 'upi', 'app', 'payment', null]));
  });

  test('the Dart filter still gives every answer in the fixture', () {
    final wrong = <String>[];
    for (final c in cases) {
      final got = ContactFilter.check(c['text'] as String, recent: (c['recent'] as List).cast<String>())?.name;
      if (got != c['kind']) wrong.add('${(c['text'] as String).replaceAll('\n', ' ')} -> $got, fixture ${c['kind']}');
    }
    expect(wrong, isEmpty);
  });

  test('the strike ladder numbers match functions/src/chatScan.js', () {
    final js = File('functions/src/chatScan.js').readAsStringSync();
    expect(ChatLadder.blockFor(3), const Duration(hours: 24));
    expect(ChatLadder.blockFor(4), const Duration(days: 3));
    expect(ChatLadder.blockFor(5), const Duration(days: 7));
    expect(js, contains('if (strikes >= 5) return 7 * DAY;'));
    expect(js, contains('if (strikes === 4) return 3 * DAY;'));
    expect(js, contains('if (strikes === 3) return DAY;'));
  });
}
