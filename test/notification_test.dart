import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/app_notification.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/notification_service.dart';
import 'package:transport_app/core/services/rating_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/features/notifications/notifications_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<String> acceptedBooking() async {
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000,
        pickupDate: DateTime(2026, 10, 5), notes: '');
    uid = 'driver1';
    await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    return BookingService.accept(loadId: loadId, vehicle: (await VehicleService.fetchMyActive()).first);
  }

  Future<List<Map<String, dynamic>>> notificationsFor(String user) async =>
      (await db.collection('notifications').where('userId', isEqualTo: user).get()).docs.map((d) => d.data()).toList();

  test('accept, status changes and ratings notify the other party', () async {
    final id = await acceptedBooking();
    var customer = await notificationsFor('customer1');
    expect(customer.single['type'], NotificationType.loadAccepted);
    expect(customer.single['relatedId'], id);
    expect(customer.single['message'], 'Delhi → Mumbai');
    expect(customer.single['read'], isFalse);

    for (var i = 0; i < 3; i++) {
      await BookingService.advance(id);
    }
    customer = await notificationsFor('customer1');
    expect(customer.where((n) => n['type'] == NotificationType.statusChanged).map((n) => n['status']),
        unorderedEquals(['picked_up', 'in_transit', 'delivered']));
    expect(await notificationsFor('driver1'), isEmpty, reason: 'actors are not notified of their own actions');

    uid = 'customer1';
    await RatingService.rate(booking: Booking.fromDoc(await db.collection('bookings').doc(id).get()), stars: 5);
    final driver = await notificationsFor('driver1');
    expect(driver.single['type'], NotificationType.ratingReceived);
    expect(driver.single['message'], startsWith('5★'));
  });

  test('unread count and mark read', () async {
    await acceptedBooking();
    uid = 'customer1';
    expect(await NotificationService.watchUnreadCount().first, 1);
    final list = (await db.collection('notifications').where('userId', isEqualTo: 'customer1').get())
        .docs
        .map(AppNotification.fromDoc)
        .toList();
    await NotificationService.markRead(list.single.id);
    expect((await notificationsFor('customer1')).single['read'], isTrue);
  });

  testWidgets('bell shows unread badge; tapping a notification marks it read and opens the booking', (tester) async {
    late String bookingId;
    await tester.runAsync(() async {
      bookingId = await acceptedBooking();
      await BookingService.advance(bookingId);
    });
    uid = 'customer1';
    String? opened;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(appBar: AppBar(actions: [NotificationBell(onOpenBooking: (id) => opened = id)])),
    ));
    await settle(tester);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byType(NotificationBell));
    await settle(tester);
    expect(find.text('A driver accepted your load'), findsOneWidget);
    expect(find.text('Trip update: Picked up'), findsOneWidget);

    await tester.tap(find.text('Trip update: Picked up'));
    await settle(tester);
    expect(opened, bookingId);
    final unread = (await tester.runAsync(() => notificationsFor('customer1')))!.where((n) => n['read'] == false);
    expect(unread, hasLength(1));

    await tester.tap(find.text('Mark all read'));
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('2'), findsNothing);
    expect(find.text('1'), findsNothing);
  });
}
