import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/connectivity_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/trip_action_queue.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/widgets/sync_indicator.dart';
import 'package:transport_app/driver/driver_trip_screen.dart';

import 'test_utils.dart';

/// MASTER-6 Task 23: trip steps done offline wait and go out later.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    uid = 'driver1';
    TripActionQueue.count.value = 0;
    ConnectivityService.online.value = true;
  });
  tearDown(() => ConnectivityService.online.value = true);

  QueuedAction act(String id, String from, {String? otp}) => QueuedAction(bookingId: id, from: from, otp: otp, queuedAt: DateTime(2026, 10, 9));

  test('network errors are recognised; others are not', () {
    expect(TripActionQueue.isNetworkError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')), isTrue);
    expect(TripActionQueue.isNetworkError(FirebaseException(plugin: 'cloud_firestore', code: 'deadline-exceeded')), isTrue);
    expect(TripActionQueue.isNetworkError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')), isFalse);
    expect(TripActionQueue.isNetworkError(StateError('Booking already delivered')), isFalse);
    expect(TripActionQueue.isNetworkError(Exception('SocketException: Failed host lookup')), isTrue);
  });

  test('enqueue keeps one entry per booking and step (newest wins), caps the queue, and updates the count', () async {
    await TripActionQueue.enqueue(act('b1', 'accepted'));
    await TripActionQueue.enqueue(act('b1', 'accepted', otp: '123456'));
    await TripActionQueue.enqueue(act('b1', 'loading'));
    final list = await TripActionQueue.pending();
    expect(list.length, 2);
    expect((list.first.from, list.first.otp), ('accepted', '123456')); // the newest (b1, accepted) replaced the first one
    expect(TripActionQueue.count.value, 2);
    for (var i = 0; i < 30; i++) {
      await TripActionQueue.enqueue(act('x$i', 'accepted'));
    }
    expect((await TripActionQueue.pending()).length, TripActionQueue.maxQueued);
    expect((await TripActionQueue.pending()).last.bookingId, 'x29');
  });

  test('flush sends in order, drops a step the trip has moved past or whose code was wrong, and stops at the first network failure', () async {
    await TripActionQueue.enqueue(act('a', 'accepted'));
    await TripActionQueue.enqueue(act('b', 'accepted'));
    await TripActionQueue.enqueue(act('c', 'loading', otp: '111111'));
    await TripActionQueue.enqueue(act('d', 'accepted'));
    await TripActionQueue.enqueue(act('e', 'accepted'));
    final sentOrder = <String>[];
    final status = {'a': 'accepted', 'b': 'driver_arriving', 'c': 'loading', 'd': 'accepted', 'e': 'accepted'};
    final r = await TripActionQueue.flush(
      statusOf: (id) async => status[id],
      send: (id, {otp, pickup, delivery}) async {
        if (id == 'c') throw WrongOtpException();
        if (id == 'd') throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
        sentOrder.add(id);
        return 'ok';
      },
    );
    expect(sentOrder, ['a']);
    expect(r.sent, 1);
    expect(r.dropped.map((d) => '${d.bookingId}:${d.why}'), ['b:moved', 'c:otp']);
    expect(r.left, 2); // d (failed on the network) and e (not tried)
    expect((await TripActionQueue.pending()).map((x) => x.bookingId), ['d', 'e']);
    expect(TripActionQueue.count.value, 2);
  });

  test('a booking that is gone is dropped; an empty queue does nothing', () async {
    expect((await TripActionQueue.flush(statusOf: (_) async => null, send: (id, {otp, pickup, delivery}) async => 'x')).sent, 0);
    await TripActionQueue.enqueue(act('z', 'accepted'));
    final r = await TripActionQueue.flush(statusOf: (_) async => null, send: (id, {otp, pickup, delivery}) async => 'x');
    expect(r.dropped.single.why, 'gone');
    expect(await TripActionQueue.pending(), isEmpty);
  });

  test('proofs survive the round trip into the queue and out to the send', () async {
    await TripActionQueue.enqueue(QueuedAction(bookingId: 'p', from: 'loading', otp: '482913', pickup: const PickupProof(packages: 40, weightTons: 7.5, sealNumber: 'S1').toMap(), queuedAt: DateTime(2026, 10, 9)));
    PickupProof? got;
    String? gotOtp;
    await TripActionQueue.flush(statusOf: (_) async => 'loading', send: (id, {otp, pickup, delivery}) async {
      got = pickup;
      gotOtp = otp;
      return 'picked_up';
    });
    expect((got!.packages, got!.weightTons, got!.sealNumber, gotOtp), (40, 7.5, 'S1', '482913'));
  });

  testWidgets('the indicator shows how many wait and Send now flushes and reports', (tester) async {
    await TripActionQueue.enqueue(act('nobody', 'accepted'));
    FlushResult? seen;
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SyncIndicator(onFlushed: (r) => seen = r)))));
    await settle(tester);
    expect(find.text('1 update(s) waiting to be sent'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('syncNow')));
    await settle(tester);
    expect(seen, isNotNull);
    expect(seen!.dropped.single.why, 'gone'); // no such booking in the fake database
    expect(find.byKey(const ValueKey('syncIndicator')), findsNothing);
  });

  Future<String> createBooking() async {
    uid = 'customer1';
    final loadId = await LoadService.post(pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: null, pickupDate: DateTime(2026, 10, 5), notes: '');
    uid = 'driver1';
    await db.collection('users').doc('driver1').set({'driverName': 'Ramesh', 'phone': '+919800000000'});
    await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).single;
    return BookingService.accept(loadId: loadId, vehicle: vehicle);
  }

  testWidgets('offline, the trip button saves the step; when the phone is online again it is sent', (tester) async {
    late String id;
    await tester.runAsync(() async => id = await createBooking());
    ConnectivityService.online.value = false;
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: DriverTripScreen(bookingId: id))));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Start: going to pickup'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Start: going to pickup'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect(find.textContaining('Saved on this phone'), findsOneWidget);
    expect((await db.collection('bookings').doc(id).get())['status'], BookingStatus.accepted); // nothing sent yet
    expect(TripActionQueue.count.value, 1);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000)); // back to the top
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('syncIndicator')), findsOneWidget);
    // back online: the indicator sends by itself
    ConnectivityService.online.value = true;
    await settle(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect((await db.collection('bookings').doc(id).get())['status'], BookingStatus.driverArriving);
    expect(TripActionQueue.count.value, 0);
  });
}
