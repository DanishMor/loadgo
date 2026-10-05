import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_dashboard_screen.dart';
import 'package:transport_app/admin/admin_trends_section.dart';
import 'package:transport_app/core/analytics/admin_trends.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

final now = DateTime(2026, 10, 20, 15);

Booking b(String id, DateTime at, {String status = 'accepted', String driver = 'd1', String from = 'Pune', String to = 'Delhi', int? paise = 100000}) => Booking(
      id: id, loadId: id, driverId: driver, vehicleId: 'v', customerId: 'c', status: status, pickup: from, drop: to, cargoType: 'x', weight: 1,
      vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1',
      timeline: {'accepted': at}, agreedFarePaise: paise,
    );

void main() {
  final sample = [
    b('1', DateTime(2026, 10, 20, 9), status: 'delivered', paise: 200000),
    b('2', DateTime(2026, 10, 20, 11), paise: 100000),
    b('3', DateTime(2026, 10, 19, 11), status: 'cancelled', paise: 999900),
    b('4', DateTime(2026, 10, 15), driver: 'd2', from: 'Mumbai', to: 'Surat', status: 'delivered', paise: 50000),
    b('5', DateTime(2026, 10, 12), driver: 'd2', from: 'Pune', to: 'Delhi', paise: 70000),
    b('6', DateTime(2026, 9, 25), driver: 'd3', status: 'delivered', paise: 80000), // 25 days ago
    b('7', DateTime(2026, 7, 1), driver: 'd4', paise: 90000), // outside 30 days
    b('8', DateTime(2026, 10, 21), driver: 'd5', paise: 90000), // in the future: ignored
  ];

  test('30 days: counts, cancel rate, GMV without cancelled, active drivers', () {
    final t = AdminTrends.from(sample, now: now);
    expect((t.bookings, t.delivered, t.cancelled), (6, 3, 1));
    expect(t.cancellationRate, closeTo(1 / 6, 1e-9));
    expect(t.gmvPaise, 200000 + 100000 + 50000 + 70000 + 80000);
    expect(t.deliveredPaise, 200000 + 50000 + 80000);
    expect(t.activeDrivers, 3, reason: 'd1, d2, d3; d4 is outside, d5 is in the future');
    expect(t.daily.length, 30);
    expect(t.daily.last.day, DateTime(2026, 10, 20));
    expect((t.daily.last.bookings, t.daily.last.delivered, t.daily.last.gmvPaise), (2, 1, 300000));
    final cancelledDay = t.daily.firstWhere((d) => d.day == DateTime(2026, 10, 19));
    expect((cancelledDay.bookings, cancelledDay.gmvPaise), (1, 0));
  });

  test('7 days and 90 days change the window', () {
    final week = AdminTrends.from(sample, now: now, days: 7);
    expect((week.bookings, week.activeDrivers, week.daily.length), (4, 2, 7));
    final long = AdminTrends.from(sample, now: now, days: 90);
    expect(long.bookings, 6, reason: 'July 1 is 111 days back');
    expect(long.activeDrivers, 3);
    expect(AdminTrends.from(sample, now: now, days: 120).bookings, 7);
  });

  test('routes and cities use the offline city table, busiest first, cancelled left out', () {
    final t = AdminTrends.from(sample, now: now);
    expect(t.topRoutes.first.route, 'Pune → Delhi');
    expect(t.topRoutes.first.count, 4);
    expect(t.topRoutes.map((r) => r.route), contains('Mumbai → Surat'));
    expect(t.cities.first.city, 'Pune');
    expect(t.cities.first.count, 4);
    final alias = AdminTrends.from([b('a', now, from: 'bombay', to: 'Pune'), b('b', now, from: 'Andheri, Mumbai', to: 'Pune')], now: now);
    expect(alias.cities.single.count, 2);
    expect(AdminTrends.from(const [], now: now).cancellationRate, isNull);
  });

  test('CSV has days, routes and cities blocks', () {
    final csv = AdminTrends.from(sample, now: now, days: 7).toCsv().split('\n');
    expect(csv.first, 'date,bookings,delivered,gmv_rupees');
    expect(csv[7], '2026-10-20,2,1,3000.00');
    expect(csv, contains('route,bookings'));
    expect(csv, contains('pickup_city,bookings'));
    expect(csv.any((l) => l.startsWith('"Pune → Delhi",')), isTrue);
  });

  testWidgets('section: numbers, bars, range switch and CSV copy', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AdminTrendsSection(load: () async => sample, clock: () => now)))));
    await settle(tester);
    expect(find.text('6'), findsWidgets);
    expect((tester.widget(find.byKey(const ValueKey('trendBookings'))) as Text).data, '6');
    expect((tester.widget(find.byKey(const ValueKey('trendCancelRate'))) as Text).data, '17%');
    expect((tester.widget(find.byKey(const ValueKey('trendActiveDrivers'))) as Text).data, '3');
    expect(find.byKey(const ValueKey('bar_10_20')), findsOneWidget);
    expect(find.byKey(const ValueKey('route_Pune → Delhi')), findsOneWidget);
    expect(find.byKey(const ValueKey('city_Pune')), findsOneWidget);
    await tester.tap(find.text('7 days'));
    await settle(tester);
    expect((tester.widget(find.byKey(const ValueKey('trendBookings'))) as Text).data, '4');
    await tester.tap(find.byKey(const ValueKey('trendsCsv')));
    await settle(tester);
    expect(copied, startsWith('date,bookings,delivered,gmv_rupees'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminTrendsSection(load: () async => const [], clock: () => now))));
    await settle(tester);
    expect(find.byKey(const ValueKey('trendNone')), findsOneWidget);
  });

  testWidgets('the analytics screen shows the trends under the counters', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    await db.collection('users').doc('u1').set({'name': 'A'});
    await db.collection('bookings').doc('x1').set({
      'loadId': 'x1', 'driverId': 'd1', 'vehicleId': 'v', 'customerId': 'c', 'status': 'delivered', 'pickup': 'Pune', 'drop': 'Delhi', 'cargoType': 'x',
      'weight': 1, 'vehicleType': '20ft', 'notes': '', 'vehicleNumber': 'MH12AB1', 'driverName': 'D', 'driverPhone': '1',
      'timeline': {'accepted': Timestamp.now()}, 'agreedFarePaise': 150000, 'createdAt': Timestamp.now(),
    });
    expect((await AdminConsoleService.recentBookings()).length, 1);
    await tester.pumpWidget(const MaterialApp(home: AdminAnalyticsScreen()));
    await settle(tester);
    expect(find.byKey(const ValueKey('totalUsers')), findsOneWidget);
    expect((tester.widget(find.byKey(const ValueKey('trendBookings'))) as Text).data, '1');
  });
}
