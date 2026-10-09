import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_pilot_control_screen.dart';
import 'package:transport_app/core/admin/pilot_control.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/server_clock.dart';

import 'test_utils.dart';

/// MASTER-6 Task 3: the pilot control room.
void main() {
  test('unfilled: only loads older than 30 minutes; a load without a time yet is not counted', () {
    final now = DateTime(2026, 10, 9, 12);
    expect(PilotControl.unfilled([now.subtract(const Duration(minutes: 29)), now.subtract(const Duration(minutes: 30)), now.subtract(const Duration(hours: 5)), null], now), 2);
    expect(PilotControl.dayStart(DateTime(2026, 10, 9, 23, 59)), DateTime(2026, 10, 9));
    expect(const PilotControl().needsAttention, isFalse);
    expect(const PilotControl(openSos: 1).needsAttention, isTrue);
    expect(const PilotControl(unfilledLoads: 2).needsAttention, isTrue);
    expect(const PilotControl(openTickets: 9, runningTrips: 4).needsAttention, isFalse);
  });

  test('the service counts today, trips, SOS and tickets from the database', () async {
    ServerClock.reset();
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'a1');
    final now = DateTime.now();
    Timestamp ago(Duration d) => Timestamp.fromDate(now.subtract(d));
    await db.collection('users').doc('u1').set({'createdAt': Timestamp.fromDate(PilotControl.dayStart(now).add(const Duration(seconds: 1)))});
    await db.collection('users').doc('u2').set({'createdAt': ago(const Duration(days: 3))});
    await db.collection('loads').doc('l1').set({'status': 'open', 'createdAt': ago(const Duration(hours: 2))});
    await db.collection('loads').doc('l2').set({'status': 'open', 'createdAt': ago(const Duration(minutes: 5))});
    await db.collection('loads').doc('l3').set({'status': 'matched', 'createdAt': ago(const Duration(hours: 2))});
    await db.collection('bookings').doc('b1').set({'status': 'in_transit'});
    await db.collection('bookings').doc('b2').set({'status': 'delivered'});
    await db.collection('sos_alerts').doc('s1').set({'status': 'open'});
    await db.collection('sos_alerts').doc('s2').set({'status': 'resolved'});
    await db.collection('tickets').doc('t1').set({'status': 'in_progress'});
    await db.collection('driver_presence').doc('d1').set({'mode': 'nearby', 'sharedUntil': Timestamp.fromDate(now.add(const Duration(hours: 1)))});
    await db.collection('driver_presence').doc('d2').set({'mode': 'nearby', 'sharedUntil': ago(const Duration(hours: 1))});
    final c = await AdminConsoleService.pilotControl();
    expect(c.signupsToday, 1);
    expect(c.openLoads, 2);
    expect(c.unfilledLoads, 1);
    expect(c.runningTrips, 1);
    expect(c.openSos, 1);
    expect(c.openTickets, 1);
    expect(c.driversSharing, 1);
  });

  testWidgets('the screen shows the banner and the numbers; refresh asks again', (tester) async {
    var calls = 0;
    Future<PilotControl> load() async => ++calls == 1 ? const PilotControl(openSos: 2, runningTrips: 5) : const PilotControl();
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: AdminPilotControlScreen(load: load))));
    await settle(tester);
    expect(find.text('Needs a person now'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('pcN_sos'))).data, '2');
    expect(tester.widget<Text>(find.byKey(const ValueKey('pcN_trips'))).data, '5');
    await tester.tap(find.byKey(const ValueKey('pcRefresh')));
    await settle(tester);
    expect(find.textContaining('All quiet'), findsOneWidget);
  });
}
