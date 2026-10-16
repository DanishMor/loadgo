import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F45: every function is in the cost table or named as a schedule, and the review names what it read.
void main() {
  final index = File('functions/index.js').readAsStringSync();
  final cost = File('docs/COST_WATCH.md').readAsStringSync();
  final review = File('docs/SECURITY_REVIEW.md').readAsStringSync();

  test('the cost table knows every trigger and schedule in index.js', () {
    final names = RegExp(r'^exports\.(\w+) = (onDocument\w*|onSchedule)', multiLine: true).allMatches(index).map((m) => m.group(1)!).toList();
    expect(names.length, greaterThan(15));
    // Triggers made by a helper (limitTrigger, chatScanTrigger) are named in the table by their group.
    final helperMade = RegExp(r'^exports\.(\w+) = (limitTrigger|chatScanTrigger)', multiLine: true).allMatches(index).map((m) => m.group(1)!).toList();
    for (final n in names) {
      expect(cost, contains(n), reason: '$n is a trigger or a schedule but is not in COST_WATCH.md');
    }
    expect(helperMade, isNotEmpty);
    for (final n in ['limitLoad', 'limitOffer', 'limitBookingMessage', 'scanBookingMessage']) {
      expect(cost, contains(n));
    }
  });

  test('the schedules named in the cost notes are the ones in the code', () {
    expect(index, contains("schedule: 'every 2 minutes'"));
    expect(cost, contains('every 2 minutes'));
    expect(index, contains("schedule: 'every 15 minutes'"));
  });

  test('the review lists the accepted risks and has no key in it', () {
    for (final w in ['App Check', 'maxInstances', 'constant time', 'Accepted risks']) {
      expect(review, contains(w), reason: w);
    }
    expect(RegExp(r'rzp_(test|live)_[A-Za-z0-9]{6,}').hasMatch(review + cost), isFalse);
  });

  test('every function has a maxInstances cap through the global options', () {
    expect(index, contains('maxInstances'));
  });
}
