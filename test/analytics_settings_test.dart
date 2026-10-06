import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/analytics/trip_stats.dart';
import 'package:transport_app/core/app_info.dart';
import 'package:transport_app/core/models/app_notification.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/user_settings.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/analytics_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/notification_service.dart';
import 'package:transport_app/core/services/settings_service.dart';
import 'package:transport_app/core/settings/settings_screen.dart';
import 'package:transport_app/customer/customer_analytics_screen.dart';
import 'package:transport_app/driver/driver_analytics_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'u1';
    Backend.useFakes(db: db, uid: () => uid);
    SettingsService.prefs.value = const NotificationPrefs();
  });

  Map<String, Object?> load(String pickup, String drop, {bool cancelled = false}) => {
        'shipperId': 'u1', 'pickup': pickup, 'drop': drop, 'cargoType': 'FMCG', 'weight': 5, 'vehicleType': '20ft',
        'status': cancelled ? 'closed' : 'open', 'cancelled': cancelled, 'notes': '',
      };

  Map<String, Object?> booking(String status, int fare, {String pickup = 'Delhi', String drop = 'Mumbai', String driver = 'd1'}) => {
        'customerId': 'u1', 'driverId': driver, 'status': status, 'agreedFarePaise': fare, 'pickup': pickup, 'drop': drop,
        'loadId': 'x', 'vehicleId': 'v', 'cargoType': 'FMCG', 'weight': 5, 'vehicleType': '20ft', 'notes': '',
        'vehicleNumber': 'N', 'driverName': 'D', 'driverPhone': '1', 'timeline': <String, Object?>{},
      };

  test('customer stats: counts, spend, success rate and normalised top routes', () async {
    for (final l in [load('Delhi', 'Mumbai'), load('New Delhi', 'Bombay'), load('Pune', 'Delhi'), load('Pune', 'Delhi', cancelled: true)]) {
      await db.collection('loads').add(l);
    }
    await db.collection('bookings').add(booking('delivered', 150000));
    await db.collection('bookings').add(booking('delivered', 50000));
    await db.collection('bookings').add(booking('in_transit', 99900));
    final s = await AnalyticsService.customer();
    expect((s.shipments, s.delivered, s.cancelled, s.spendPaise), (4, 2, 1, 200000));
    expect(s.successRate, closeTo(2 / 3, 1e-9));
    expect(s.topRoutes.first.route, 'Delhi → Mumbai');
    expect(s.topRoutes.first.count, 2);
    expect(percentText(s.successRate!), '67%');
    final empty = CustomerStats.from(const <Load>[], const <Booking>[]);
    expect(empty.successRate, isNull);
    expect(empty.topRoutes, isEmpty);
  });

  test('driver stats: trips, earnings, acceptance and cancel rate', () async {
    uid = 'd1';
    await db.collection('bookings').add(booking('delivered', 100000));
    await db.collection('bookings').add(booking('delivered', 25000));
    await db.collection('bookings').add(booking('cancelled', 0));
    await db.collection('bookings').add(booking('in_transit', 70000));
    await db.collection('bookings').add(booking('delivered', 1, driver: 'other'));
    for (final st in ['confirmed', 'selected', 'rejected', 'rejected', 'pending']) {
      await db.collection('offers').add({'driverId': 'd1', 'status': st, 'loadId': 'x', 'pricePaise': 1, 'originalPaise': 1});
    }
    final s = await AnalyticsService.driver();
    expect((s.trips, s.cancelledTrips, s.earningsPaise), (2, 1, 125000));
    expect(s.cancelRate, 0.25);
    expect(s.acceptanceRate, 0.5);
    final none = DriverStats.from(const <Booking>[], const <Offer>[]);
    expect((none.acceptanceRate, none.cancelRate), (null, null));
  });

  testWidgets('analytics screens render the numbers', (tester) async {
    await db.collection('loads').add(load('Delhi', 'Mumbai'));
    await db.collection('bookings').add(booking('delivered', 150000));
    await tester.pumpWidget(const MaterialApp(home: CustomerAnalyticsScreen()));
    await settle(tester);
    expect(find.text('Delhi → Mumbai'), findsOneWidget);
    expect(find.textContaining('1,500'), findsOneWidget);

    uid = 'd1';
    await tester.pumpWidget(const MaterialApp(home: DriverAnalyticsScreen()));
    await settle(tester);
    expect(find.text('Total earnings'), findsOneWidget);
    expect(find.textContaining('1,500'), findsOneWidget);
  });

  test('notification prefs decide which notifications show', () async {
    await db.collection('notifications').add({'userId': 'u1', 'type': NotificationType.statusChanged, 'message': 'a', 'relatedId': 'b', 'read': false, 'createdAt': Timestamp.now()});
    await db.collection('notifications').add({'userId': 'u1', 'type': NotificationType.ratingReceived, 'message': 'r', 'relatedId': 'b', 'read': false, 'createdAt': Timestamp.now()});
    expect((await NotificationService.watchMine().first), hasLength(2));
    await SettingsService.savePrefs(const NotificationPrefs(ratings: false));
    expect((await db.collection('users').doc('u1').get())['notificationPrefs'], {'bookingUpdates': true, 'ratings': false, 'promotions': true, 'payments': true, 'reminders': true});
    expect((await NotificationService.watchMine().first).map((n) => n.type), [NotificationType.statusChanged]);
    expect(await NotificationService.watchUnreadCount().first, 1);
    SettingsService.prefs.value = const NotificationPrefs();
    await SettingsService.refresh();
    expect(SettingsService.prefs.value.ratings, isFalse);
    expect(NotificationPrefs.fromMap(null).allows('anything'), isTrue);
  });

  test('consents default to off and persist; deletion request is a single pending doc', () async {
    expect((await SettingsService.loadConsents()).location, isFalse);
    await SettingsService.saveConsents(const Consents(analytics: true));
    final c = await SettingsService.loadConsents();
    expect((c.location, c.analytics, c.marketing), (false, true, false));

    expect(await SettingsService.hasPendingDeletion(), isFalse);
    await SettingsService.requestDeletion(reason: ' leaving ');
    expect(await SettingsService.hasPendingDeletion(), isTrue);
    expect((await db.collection('deletion_requests').doc('u1').get())['reason'], 'leaving');
    uid = 'admin1';
    await AdminConsoleService.setDeletionStatus('u1', 'done');
    uid = 'u1';
    expect(await SettingsService.hasPendingDeletion(), isFalse);
  });

  testWidgets('settings screen: toggles save, deletion asks first, logout calls back', (tester) async {
    var loggedOut = false;
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(onLogout: () async => loggedOut = true)));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('prefRatings')));
    await settle(tester);
    expect((await db.collection('users').doc('u1').get())['notificationPrefs']['ratings'], false);
    await tester.tap(find.byKey(const ValueKey('consentLocation')));
    await settle(tester);
    expect((await db.collection('users').doc('u1').get())['consents']['location'], true);

    await tester.tap(find.byKey(const ValueKey('settingsTerms')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tosC1')), findsOneWidget);
    expect(find.textContaining('Placeholder'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text(appVersion), findsOneWidget);
    // Deletion opens its own screen; nothing is deleted until DELETE is typed.
    await tester.tap(find.byKey(const ValueKey('deleteAccount')));
    await settle(tester);
    expect(find.byKey(const ValueKey('delConfirm')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect((await db.collection('users').doc('u1').get()).exists, isTrue);

    await tester.tap(find.byKey(const ValueKey('settingsLogout')));
    await tester.pump();
    expect(loggedOut, isTrue);
  });

  test('appVersion matches pubspec', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':')[1].trim(), appVersion);
  });
}
