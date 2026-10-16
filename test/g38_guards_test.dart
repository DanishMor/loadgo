import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G38: things found in the bug hunt that a test can keep fixed.
void main() {
  test('P3-B2: Analytics collects nothing until the person agrees (the manifest turns auto-collection off)', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(m, contains('firebase_analytics_collection_enabled'));
    expect(RegExp(r'firebase_analytics_collection_enabled"\s+android:value="false"').hasMatch(m), isTrue);
    final a = File('lib/core/services/analytics_events.dart').readAsStringSync();
    expect(a, contains('setAnalyticsCollectionEnabled(on)'));
  });

  test('P3-B1: the live trip location stops when the sign-in ends', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(RegExp(r'else \{[\s\S]{0,400}LiveLocationSharer\.stop\(\)').hasMatch(main), isTrue);
  });

  test('P3-B3: the trip SMS needs the booking to belong to the person (the server code checks it)', () {
    final s = File('functions/src/sms.js').readAsStringSync();
    expect(s, contains("booking.customerId !== n.userId"));
  });
}
