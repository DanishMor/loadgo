import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_pilot_report_screen.dart';
import 'package:transport_app/core/admin/pilot_report.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/server_clock.dart';

import 'test_utils.dart';

/// MASTER-6 Task 5: the daily / weekly pilot report.
void main() {
  String label(String k) => k;

  test('periods: today from midnight; the week is seven calendar days including today (month edge too)', () {
    expect(PilotReport.periodStart(DateTime(2026, 10, 9, 15), weekly: false), DateTime(2026, 10, 9));
    expect(PilotReport.periodStart(DateTime(2026, 10, 9, 15), weekly: true), DateTime(2026, 10, 3));
    expect(PilotReport.periodStart(DateTime(2026, 3, 2), weekly: true), DateTime(2026, 2, 24));
  });

  test('percentages: whole numbers, none without a base, fill never above 100', () {
    final none = PilotReport(weekly: false, from: _t, to: _t);
    expect(none.fillPercent, isNull);
    expect(none.deliveredPercent, isNull);
    final r = PilotReport(weekly: false, from: _t, to: _t, loads: 3, bookings: 2, delivered: 2, cancelled: 1);
    expect(r.fillPercent, 66);
    expect(r.deliveredPercent, 66);
    expect(PilotReport(weekly: false, from: _t, to: _t, loads: 1, bookings: 4).fillPercent, 100);
  });

  test('text: title with the date(s), one line per number, no personal data fields', () {
    final r = PilotReport(weekly: true, from: _t, to: _t2, signups: 4, loads: 10, bookings: 6, delivered: 5, cancelled: 1, sos: 0, tickets: 2);
    final lines = r.text(label).split('\n');
    expect(lines.first, 'weeklyTitle (2026-10-03 - 2026-10-09)');
    expect(lines, containsAll(['signups: 4', 'loads: 10', 'bookings: 6', 'delivered: 5', 'cancelled: 1', 'fill: 60%', 'deliveredRate: 83%', 'sos: 0', 'tickets: 2']));
    expect(PilotReport(weekly: false, from: _t, to: _t).text(label).split('\n').first, 'dailyTitle (2026-10-03)');
  });

  test('the service counts the period only', () async {
    ServerClock.reset();
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'a');
    final now = DateTime.now();
    Timestamp at(Duration ago) => Timestamp.fromDate(now.subtract(ago));
    final today = Timestamp.fromDate(DateTime(now.year, now.month, now.day).add(const Duration(seconds: 1)));
    await db.collection('users').doc('u1').set({'createdAt': today});
    await db.collection('users').doc('u2').set({'createdAt': at(const Duration(days: 3))});
    await db.collection('loads').doc('l1').set({'createdAt': today});
    await db.collection('bookings').doc('b1').set({'createdAt': today, 'status': 'delivered'});
    await db.collection('bookings').doc('b2').set({'createdAt': today, 'status': 'cancelled'});
    await db.collection('bookings').doc('b3').set({'createdAt': at(const Duration(days: 30)), 'status': 'delivered'});
    final day = await AdminConsoleService.pilotReport(weekly: false);
    expect((day.signups, day.loads, day.bookings, day.delivered, day.cancelled), (1, 1, 2, 1, 1));
    final week = await AdminConsoleService.pilotReport(weekly: true);
    expect(week.signups, 2);
  });

  testWidgets('the screen shows the text, switches period and copies it', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final asked = <bool>[];
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: AdminPilotReportScreen(load: (w) async {
        asked.add(w);
        return PilotReport(weekly: w, from: _t, to: _t2, signups: 7);
      })),
    ));
    await settle(tester);
    expect(find.textContaining('Daily pilot report'), findsOneWidget);
    expect(find.textContaining('Sign-ups: 7'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prWeek')));
    await settle(tester);
    expect(asked, [false, true]);
    expect(find.textContaining('Weekly pilot report'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prCopy')));
    await settle(tester);
    expect(copied, contains('Sign-ups: 7'));
  });
}

final _t = DateTime(2026, 10, 3);
final _t2 = DateTime(2026, 10, 9);
