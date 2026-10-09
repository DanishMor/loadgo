import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_config_screen.dart';
import 'package:transport_app/admin/admin_dashboard_screen.dart';
import 'package:transport_app/admin/admin_entry.dart';
import 'package:transport_app/admin/admin_lists.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/audit_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'admin1';
    Backend.useFakes(db: db, uid: () => uid);
  });

  Widget app(Widget home) => MaterialApp(home: Scaffold(body: home));

  testWidgets('admin entry shows only for allowlisted users', (tester) async {
    await tester.pumpWidget(app(const AdminEntryTile()));
    await settle(tester);
    expect(find.byKey(const ValueKey('profileAdmin')), findsNothing);

    await db.collection('admins').doc('admin1').set({'by': 'console'});
    await tester.pumpWidget(app(const AdminEntryTile(key: ValueKey('again'))));
    await settle(tester);
    expect(find.byKey(const ValueKey('profileAdmin')), findsOneWidget);
    expect(await AdminConsoleService.isAdmin(), isTrue);
    uid = 'someone';
    expect(await AdminConsoleService.isAdmin(), isFalse);
  });

  test('user search matches name, phone and uid', () {
    final d = {'name': 'Anil Kumar', 'phone': '+919800000000'};
    expect(AdminConsoleService.userMatches(d, 'u1', 'anil'), isTrue);
    expect(AdminConsoleService.userMatches(d, 'u1', '9800'), isTrue);
    expect(AdminConsoleService.userMatches(d, 'abc123', 'ABC'), isTrue);
    expect(AdminConsoleService.userMatches(d, 'u1', 'zzz'), isFalse);
    expect(AdminConsoleService.userMatches(d, 'u1', '  '), isTrue);
  });

  testWidgets('users screen filters by the search text', (tester) async {
    await db.collection('users').doc('u1').set({'name': 'Anil', 'phone': '+911'});
    await db.collection('users').doc('u2').set({'driverName': 'Suresh', 'phone': '+912'});
    await tester.pumpWidget(const MaterialApp(home: AdminUsersScreen()));
    await settle(tester);
    expect(find.text('Anil'), findsOneWidget);
    expect(find.text('Suresh'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('userSearch')), 'sur');
    await tester.pumpAndSettle();
    expect(find.text('Anil'), findsNothing);
    expect(find.text('Suresh'), findsOneWidget);
  });

  testWidgets('analytics counters: users, status counts and delivered fare sum', (tester) async {
    await db.collection('users').doc('u1').set({'name': 'A', 'roles': ['customer']});
    await db.collection('users').doc('u2').set({'driverName': 'B', 'roles': ['driver']});
    await db.collection('loads').add({'status': 'open'});
    await db.collection('loads').add({'status': 'matched'});
    await db.collection('bookings').add({'status': 'delivered', 'agreedFarePaise': 150000});
    await db.collection('bookings').add({'status': 'delivered', 'agreedFarePaise': 50000});
    await db.collection('bookings').add({'status': 'cancelled', 'agreedFarePaise': 99900});
    final c = await AdminConsoleService.counters();
    expect(c.users, 2);
    expect(c.drivers, 1);
    expect(c.loadsByStatus, {'open': 1, 'matched': 1, 'closed': 0});
    expect(c.bookingsByStatus['delivered'], 2);
    expect(c.bookingsByStatus['cancelled'], 1);
    expect(c.deliveredFarePaise, 200000);

    await tester.pumpWidget(const MaterialApp(home: AdminAnalyticsScreen()));
    await settle(tester);
    expect(find.byKey(const ValueKey('totalUsers')), findsOneWidget);
    expect(find.textContaining('2,000'), findsOneWidget);
  });

  group('reassign', () {
    late Booking booking;

    setUp(() async {
      uid = 'customer1';
      final loadId = await LoadService.post(
          pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000,
          pickupDate: DateTime(2026, 10, 5), notes: '');
      uid = 'driver1';
      await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
      final v1 = (await VehicleService.fetchMyActive()).first;
      final id = await BookingService.accept(loadId: loadId, vehicle: v1);
      uid = 'driver2';
      await db.collection('users').doc('driver2').set({'driverName': 'Suresh', 'phone': '+912'});
      await VehicleService.add(number: 'KA01CD5678', type: '20ft', capacity: 10, rcNumber: 'RC2');
      booking = Booking.fromDoc(await db.collection('bookings').doc(id).get());
      uid = 'admin1';
    });

    test('moves booking, load and vehicle availability, and writes an audit event', () async {
      await AdminConsoleService.reassignDriver(booking, 'ka01 cd5678');
      final b = (await db.collection('bookings').doc(booking.id).get()).data()!;
      expect((b['driverId'], b['vehicleNumber'], b['driverName']), ('driver2', 'KA01CD5678', 'Suresh'));
      expect((await db.collection('loads').doc(booking.loadId).get())['driverId'], 'driver2');
      expect((await db.collection('vehicles').doc(booking.vehicleId).get())['availability'], 'available');
      final events = await db.collection('audit_events').where('type', isEqualTo: AuditType.reassign).get();
      expect(events.docs, hasLength(1));
    });

    test('refuses unknown vehicle, same driver and late statuses', () async {
      expect(AdminConsoleService.reassignDriver(booking, 'ZZ00ZZ0000'), throwsA(isA<ReassignException>()));
      expect(AdminConsoleService.reassignDriver(booking, 'MH12AB1234'), throwsA(isA<ReassignException>()));
      await db.collection('bookings').doc(booking.id).update({'status': 'in_transit'});
      final late = Booking.fromDoc(await db.collection('bookings').doc(booking.id).get());
      expect(AdminConsoleService.reassignDriver(late, 'KA01CD5678'), throwsA(isA<ReassignException>()));
    });
  });

  testWidgets('suspend a vehicle and acknowledge an SOS from the admin screens', (tester) async {
    await db.collection('vehicles').doc('v1').set({'number': 'MH12AB1234', 'type': '20ft', 'availability': 'available', 'createdAt': Timestamp.now()});
    await tester.pumpWidget(const MaterialApp(home: AdminVehiclesScreen()));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('suspend_v1')));
    await settle(tester);
    expect((await db.collection('vehicles').doc('v1').get())['availability'], 'suspended');

    await db.collection('sos_alerts').doc('s1').set({'userId': 'd1', 'status': 'open', 'createdAt': Timestamp.now()});
    await tester.pumpWidget(const MaterialApp(home: AdminSosScreen()));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ack_s1')));
    await settle(tester);
    final s = (await db.collection('sos_alerts').doc('s1').get()).data()!;
    expect((s['status'], s['handledBy']), ('acknowledged', 'admin1'));
  });

  testWidgets('config editor saves valid JSON and refuses invalid JSON', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ConfigEditorScreen(docId: 'pricing', titleKey: 'adminPricing')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('configJson')), '{"platformFeePercent": 7}');
    await tester.tap(find.byKey(const ValueKey('saveConfig')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('cfgConfirm'))); // the diff preview
    await settle(tester);
    expect((await db.collection('config').doc('pricing').get())['platformFeePercent'], 7);
    await tester.pump(const Duration(seconds: 8)); // let the "saved" snackbar go
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('configJson')), '{oops');
    await tester.tap(find.byKey(const ValueKey('saveConfig')));
    await settle(tester);
    expect(find.text('This is not valid JSON'), findsOneWidget);
    expect((await db.collection('config').doc('pricing').get())['platformFeePercent'], 7);
  });

  testWidgets('dashboard lists every admin screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminDashboardScreen()));
    for (final k in ['adminAnalytics', 'adminUsers', 'adminVehicles', 'adminLoads', 'adminBookings', 'adminTickets', 'adminSos', 'adminReports', 'adminConfig']) {
      await tester.scrollUntilVisible(find.byKey(ValueKey('admin_$k')), 100);
      expect(find.byKey(ValueKey('admin_$k')), findsOneWidget);
    }
  });
}
