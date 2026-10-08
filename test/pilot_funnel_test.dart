import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_pilot_funnel_screen.dart';
import 'package:transport_app/core/admin/pilot_funnel.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-5 Task 39: where people stop before a first delivery.
void main() {
  late FakeFirebaseFirestore db;

  Future<void> seed() async {
    // customers: c1 delivered, c2 posted a load only, c3 profile only, c4 signed up
    await db.collection('users').doc('c1').set({'role': 'customer', 'profileComplete': true});
    await db.collection('users').doc('c2').set({'role': 'customer', 'profileComplete': true});
    await db.collection('users').doc('c3').set({'role': 'customer', 'profileComplete': true});
    await db.collection('users').doc('c4').set({'role': 'customer'});
    // drivers: d1 delivered, d2 verified with a trip in progress, d3 documents only, d4 profile only
    await db.collection('users').doc('d1').set({'role': 'driver', 'driverProfileComplete': true, 'kycComplete': true, 'verified': true});
    await db.collection('users').doc('d2').set({'role': 'driver', 'driverProfileComplete': true, 'kycComplete': true, 'verified': true});
    await db.collection('users').doc('d3').set({'role': 'driver', 'driverProfileComplete': true, 'kycComplete': true});
    await db.collection('users').doc('d4').set({'role': 'driver', 'driverProfileComplete': true});
    // a driver who skipped KYC but is verified must not count as having documents
    await db.collection('users').doc('d5').set({'role': 'driver', 'driverProfileComplete': true, 'verified': true});
    await db.collection('users').doc('t1').set({'role': 'fleet', 'fleetProfileComplete': true});
    await db.collection('loads').doc('L1').set({'shipperId': 'c1'});
    await db.collection('loads').doc('L2').set({'shipperId': 'c2'});
    await db.collection('bookings').doc('B1').set({'customerId': 'c1', 'driverId': 'd1', 'fleetOwnerId': 't1', 'status': 'delivered'});
    await db.collection('bookings').doc('B2').set({'customerId': 'c2', 'driverId': 'd2', 'status': 'in_transit'});
    await db.collection('bookings').doc('B3').set({'customerId': 'c3', 'driverId': 'd3', 'status': 'cancelled'});
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    await seed();
  });

  Map<String, int> counts(List<FunnelStep> steps) => {for (final s in steps) s.key: s.count};

  test('each step counts people who also passed the one before', () async {
    final f = await AdminConsoleService.pilotFunnel();
    expect(counts(f.customers), {'pfSignedUp': 4, 'pfProfile': 3, 'pfFirstLoad': 2, 'pfFirstDelivery': 1});
    expect(counts(f.drivers), {'pfSignedUp': 5, 'pfProfile': 5, 'pfDocuments': 3, 'pfVerified': 2, 'pfFirstTrip': 2, 'pfFirstDelivery': 1});
    expect(counts(f.transporters), {'pfSignedUp': 1, 'pfProfile': 1, 'pfFirstTrip': 1, 'pfFirstDelivery': 1});
    for (final steps in [f.customers, f.drivers, f.transporters]) {
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i].count, lessThanOrEqualTo(steps[i - 1].count));
      }
    }
  });

  test('the biggest drop is named, and no drop gives null', () {
    expect(PilotFunnel.biggestDrop(const [FunnelStep('a', 10), FunnelStep('b', 9), FunnelStep('c', 3), FunnelStep('d', 2)]), ('b', 'c', 6));
    expect(PilotFunnel.biggestDrop(const [FunnelStep('a', 3), FunnelStep('b', 3)]), isNull);
    expect(PilotFunnel.biggestDrop(const []), isNull);
  });

  testWidgets('the screen shows each role with its counts and the biggest drop', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: AdminPilotFunnelScreen())));
    await settle(tester);
    expect(find.byKey(const ValueKey('funnel_customers_pfSignedUp')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('funnel_customers_pfFirstLoad'))).data, '2');
    expect(find.byKey(const ValueKey('funnelDrop_customers')), findsOneWidget);
  });

  testWidgets('an empty project shows the empty state', (tester) async {
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'admin1');
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: AdminPilotFunnelScreen())));
    await settle(tester);
    expect(find.text('No one has signed up yet.'), findsOneWidget);
  });
}
