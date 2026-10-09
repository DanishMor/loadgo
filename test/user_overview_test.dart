import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/user_overview_card.dart';
import 'package:transport_app/core/admin/user_overview.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/admin_user_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-6 Task 11: the admin 360 view of a person.
void main() {
  test('compute: trips by side, delivered / cancelled, rating tenths, tickets, vehicles, trail newest first', () {
    final o = UserOverview.compute(
      uid: 'u1',
      user: {'chatStrikes': 2, 'verified': true, 'kycComplete': false, 'riskTier': 'review'},
      bookings: [
        {'customerId': 'u1', 'status': 'delivered'},
        {'customerId': 'u1', 'status': 'cancelled'},
        {'driverId': 'u1', 'status': 'delivered'},
        {'fleetOwnerId': 'u1', 'driverId': 'd9', 'status': 'in_transit'},
      ],
      stars: [5, 4, 4, 0, 9],
      violations: 3,
      tickets: [
        {'status': 'open'},
        {'status': 'closed'},
        {'status': 'in_progress'},
      ],
      vehicleHasExpiredPapers: [true, false, false],
      auditEvents: [
        {'type': 'user_action', 'data': {'action': 'suspend'}, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1))},
        {'type': 'verification', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 5))},
        {'type': 'x'},
      ],
    );
    expect((o.tripsAsCustomer, o.tripsAsDriver, o.delivered, o.cancelled), (2, 2, 2, 1));
    expect((o.ratingCount, o.ratingTenths), (3, 43)); // 13 / 3 = 4.33
    expect((o.strikes, o.violations, o.openTickets), (2, 3, 2));
    expect((o.vehicles, o.vehiclesWithExpiredPapers), (3, 1));
    expect((o.verified, o.kycComplete, o.riskTier), (true, false, 'review'));
    expect(o.trail.map((e) => e.type), ['verification', 'user_action', 'x']);
    expect(o.trail[1].action, 'suspend');
  });

  test('compute: an empty person gives zeros, no rating and a normal tier; the trail is capped', () {
    final o = UserOverview.compute(uid: 'u', user: null, bookings: const [], stars: const [], violations: 0, tickets: const [], vehicleHasExpiredPapers: const [], auditEvents: [for (var i = 0; i < 40; i++) {'type': 't$i'}]);
    expect(o.ratingTenths, isNull);
    expect(o.riskTier, 'normal');
    expect(o.trail.length, UserOverview.trailLimit);
  });

  test('the service reads trips, ratings, tickets, vehicles, violations and audit events of one person only', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'a1');
    await db.collection('users').doc('u1').set({'name': 'Ravi', 'chatStrikes': 1, 'verified': true});
    await db.collection('bookings').doc('b1').set({'customerId': 'u1', 'driverId': 'd1', 'status': 'delivered'});
    await db.collection('bookings').doc('b2').set({'customerId': 'x', 'driverId': 'u1', 'status': 'cancelled'});
    await db.collection('bookings').doc('b3').set({'customerId': 'x', 'driverId': 'y', 'status': 'delivered'});
    await db.collection('ratings').doc('r1').set({'ratedId': 'u1', 'stars': 5});
    await db.collection('ratings').doc('r2').set({'ratedId': 'z', 'stars': 1});
    await db.collection('tickets').doc('t1').set({'userId': 'u1', 'status': 'open'});
    await db.collection('violations').doc('u1_1').set({'userId': 'u1'});
    await db.collection('vehicles').doc('v1').set({'ownerId': 'u1', 'number': 'MH12AB1234', 'type': 'Mini', 'capacity': 3, 'status': 'active', 'availability': 'available', 'rcNumber': 'x', 'docs': {'insurance': {'number': 'I', 'expiry': Timestamp.fromDate(DateTime(2020))}}});
    await db.collection('audit_events').doc('e1').set({'type': 'user_action', 'targetId': 'u1', 'data': {'action': 'note'}, 'createdAt': Timestamp.now()});
    final o = await AdminUserService.overview('u1');
    expect((o.tripsAsCustomer, o.tripsAsDriver, o.delivered, o.cancelled), (1, 1, 1, 1));
    expect((o.ratingCount, o.ratingTenths), (1, 50));
    expect((o.strikes, o.violations, o.openTickets, o.vehicles), (1, 1, 1, 1));
    expect(o.vehiclesWithExpiredPapers, 1);
    expect(o.trail.single.action, 'note');
  });

  testWidgets('the card shows the lines and refreshes', (tester) async {
    var n = 0;
    Future<UserOverview> load(String uid) async => ++n == 1 ? const UserOverview(tripsAsCustomer: 3, ratingTenths: 47, ratingCount: 6, openTickets: 2, verified: true) : const UserOverview();
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: UserOverviewCard(uid: 'u1', load: load))))));
    await settle(tester);
    expect(find.textContaining('Trips: 3 as customer'), findsOneWidget);
    expect(find.text('Rating: 4.7 from 6 ratings'), findsOneWidget);
    expect(find.text('Open tickets: 2'), findsOneWidget);
    expect(find.textContaining('Verified: yes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('uoRefresh')));
    await settle(tester);
    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('No events yet.'), findsOneWidget);
  });
}
