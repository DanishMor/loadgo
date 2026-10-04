import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/matching/return_loads.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/truck_board.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/reminders/reminders.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/truck_board_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/customer/truck_board_screen.dart';
import 'package:transport_app/driver/empty_trucks_screen.dart';
import 'package:transport_app/driver/return_loads_section.dart';

import 'test_utils.dart';

Booking trip({String pickup = 'Delhi', String drop = 'Mumbai', String status = 'in_transit'}) => Booking(
      id: 'b1', loadId: 'own', driverId: 'd1', vehicleId: 'v', customerId: 'c', status: status, pickup: pickup, drop: drop, cargoType: 'x',
      weight: 1, vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'X', driverName: 'D', driverPhone: '1', timeline: const {},
    );

Load load(String id, String pickup, String drop, {String shipper = 'c9', String status = 'open'}) => Load(
      id: id, shipperId: shipper, pickup: pickup, drop: drop, cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: 1000,
      pickupDate: null, notes: '', status: status,
    );

void main() {
  late FakeFirebaseFirestore db;
  String uid = 'd1';
  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'd1';
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });

  Widget app(Widget w) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: w));

  Future<Vehicle> driverWithVehicle({bool verified = true}) async {
    await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh', 'verified': verified});
    final id = await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    return (await VehicleService.fetchMyActive()).firstWhere((v) => v.id == id);
  }

  group('empty truck posts', () {
    test('a verified driver posts; the board shows it to customers soonest first and hides past and closed posts', () async {
      final v = await driverWithVehicle();
      final today = DateTime.now();
      await TruckBoardService.post(vehicle: v, fromCity: 'Pune', toCity: 'Delhi', date: today.add(const Duration(days: 5)), note: 'Open body');
      final soon = await TruckBoardService.post(vehicle: v, fromCity: 'Jaipur', toCity: 'Mumbai', date: today.add(const Duration(days: 1)));
      final closed = await TruckBoardService.post(vehicle: v, fromCity: 'Agra', toCity: 'Delhi', date: today.add(const Duration(days: 2)));
      await TruckBoardService.closePost(closed);
      await db.collection('truck_posts').doc('past').set({
        'driverId': 'd1', 'fromCity': 'X', 'toCity': 'Y', 'availableDate': Timestamp.fromDate(today.subtract(const Duration(days: 3))), 'status': 'open',
      });
      uid = 'c1';
      final board = await TruckBoardService.watchOpenBoard().first;
      expect(board.map((p) => p.fromCity), ['Jaipur', 'Pune']);
      expect(board.first.id, soon);
      expect(board.first.driverName, 'Ramesh');
      expect(board.first.vehicleNumber, 'MH12AB1234');
    });

    test('refused: not verified, bad route, bad date, someone else\'s vehicle, long note', () async {
      final v = await driverWithVehicle(verified: false);
      final d = DateTime.now().add(const Duration(days: 2));
      Future<void> go({String from = 'Pune', DateTime? date, Vehicle? vehicle, String note = ''}) =>
          TruckBoardService.post(vehicle: vehicle ?? v, fromCity: from, toCity: 'Delhi', date: date ?? d, note: note).then((_) {});
      Matcher reason(String r) => throwsA(isA<TruckBoardException>().having((e) => e.reason, 'reason', r));
      await expectLater(go(), reason('driver_not_verified'));
      await db.collection('users').doc('d1').update({'verified': true});
      await expectLater(go(from: 'P'), reason('route'));
      await expectLater(go(date: DateTime.now().subtract(const Duration(days: 2))), reason('date'));
      await expectLater(go(date: DateTime.now().add(const Duration(days: 40))), reason('date'));
      await expectLater(go(note: 'n' * 201), reason('details'));
      final other = Vehicle(id: 'v2', ownerId: 'someoneElse', number: 'X', type: '20ft', capacity: 1, rcNumber: 'R', status: 'active');
      await expectLater(go(vehicle: other), reason('vehicle'));
      await go();
    });

    test('board filter: from, to, vehicle type and dates', () {
      TruckPost post(String from, String to, String type, DateTime date) => TruckPost(
          id: '$from$to', driverId: 'd', vehicleId: 'v', vehicleNumber: 'X', vehicleType: type, capacity: 5, fromCity: from, toCity: to, availableDate: date, status: 'open');
      final p = post('Pune', 'New Delhi', '20ft', DateTime(2026, 10, 10));
      expect(TruckFilter.none.matches(p), isTrue);
      expect(const TruckFilter(from: ' pun ').matches(p), isTrue);
      expect(const TruckFilter(to: 'delhi').matches(p), isTrue);
      expect(const TruckFilter(from: 'mumbai').matches(p), isFalse);
      expect(const TruckFilter(vehicleType: '14ft').matches(p), isFalse);
      expect(TruckFilter(onOrAfter: DateTime(2026, 10, 11)).matches(p), isFalse);
      expect(TruckFilter(onOrBefore: DateTime(2026, 10, 10, 23)).matches(p), isTrue);
      expect(const TruckFilter(from: ' ').isEmpty, isTrue);
    });
  });

  group('requests', () {
    Future<TruckPost> openPost() async {
      final v = await driverWithVehicle();
      final id = await TruckBoardService.post(vehicle: v, fromCity: 'Pune', toCity: 'Delhi', date: DateTime.now().add(const Duration(days: 3)));
      return TruckPost.fromDoc(id, (await db.collection('truck_posts').doc(id).get()).data()!);
    }

    test('a customer requests once per post; the driver accepts; the customer can then post a load reserved for that driver', () async {
      final post = await openPost();
      uid = 'c1';
      await db.collection('users').doc('c1').set({'role': 'customer', 'name': 'Anil'});
      final id = await TruckBoardService.sendRequest(post, pickup: 'Pune', drop: 'Delhi', weight: 6, cargoType: 'FMCG', note: 'Fragile');
      expect(id, '${post.id}_c1');
      var r = TruckRequest.fromDoc(id, (await db.collection('truck_requests').doc(id).get()).data()!);
      expect((r.status, r.driverId, r.customerName, r.vehicleType), ('pending', 'd1', 'Anil', '20ft'));

      uid = 'd1';
      expect((await TruckBoardService.watchRequestsForDriver().first).single.id, id);
      await TruckBoardService.answer(r, accept: true);
      uid = 'c1';
      r = (await TruckBoardService.watchMyRequests().first).single;
      expect(r.status, 'accepted');
      final draft = r.toLoadDraft();
      expect((draft.pickup, draft.drop, draft.weight, draft.vehicleType, draft.invitedDriverId), ('Pune', 'Delhi', 6, '20ft', 'd1'));

      final loadId = await LoadService.post(
        pickup: draft.pickup, drop: draft.drop, cargoType: 'FMCG', weight: 6, vehicleType: '20ft', budget: null,
        pickupDate: DateTime.now().add(const Duration(days: 3)), notes: '', invitedDriverId: draft.invitedDriverId,
      );
      expect(Load.fromDoc(await db.collection('loads').doc(loadId).get()).invitedDriverId, 'd1');
    });

    test('refused: own post, closed post, bad details; only the driver answers; only pending requests', () async {
      final post = await openPost();
      Matcher reason(String r) => throwsA(isA<TruckBoardException>().having((e) => e.reason, 'reason', r));
      await expectLater(TruckBoardService.sendRequest(post, pickup: 'Pune', drop: 'Delhi', weight: 1), reason('own_post'));
      uid = 'c1';
      await expectLater(TruckBoardService.sendRequest(post, pickup: 'P', drop: 'Delhi', weight: 1), reason('details'));
      await expectLater(TruckBoardService.sendRequest(post, pickup: 'Pune', drop: 'Delhi', weight: 0), reason('details'));
      await expectLater(TruckBoardService.sendRequest(post, pickup: 'Pune', drop: 'Delhi', weight: 101), reason('details'));
      final past = TruckPost(id: 'old', driverId: 'd1', vehicleId: 'v', vehicleNumber: 'X', vehicleType: '20ft', capacity: 1, fromCity: 'A', toCity: 'B', availableDate: DateTime(2020), status: 'open');
      await expectLater(TruckBoardService.sendRequest(past, pickup: 'Pune', drop: 'Delhi', weight: 1), reason('closed'));
      final id = await TruckBoardService.sendRequest(post, pickup: 'Pune', drop: 'Delhi', weight: 1);
      final r = TruckRequest.fromDoc(id, (await db.collection('truck_requests').doc(id).get()).data()!);
      await expectLater(TruckBoardService.answer(r, accept: true), reason('closed'));
      uid = 'd1';
      await TruckBoardService.answer(r, accept: false);
      final answered = TruckRequest.fromDoc(id, (await db.collection('truck_requests').doc(id).get()).data()!);
      await expectLater(TruckBoardService.answer(answered, accept: true), reason('closed'));
      expect(answered.status, 'declined');
    });

    test('the customer can withdraw a request', () async {
      final post = await openPost();
      uid = 'c1';
      final id = await TruckBoardService.sendRequest(post, pickup: 'Pune', drop: 'Delhi', weight: 1);
      await TruckBoardService.withdrawRequest(id);
      expect((await TruckBoardService.watchMyRequests().first).single.status, 'withdrawn');
    });
  });

  group('return loads', () {
    test('open loads near the drop city, return runs first, own and closed excluded, unknown places ignored', () {
      final loads = [
        load('home', 'Mumbai', 'Delhi'), // back towards the start
        load('near', 'Navi Mumbai', 'Hyderabad'), // near the drop, not home
        load('pune', 'Pune', 'Mumbai'), // ~120 km: outside the radius
        load('far', 'Chennai', 'Delhi'),
        load('mine', 'Mumbai', 'Delhi', shipper: 'me'),
        load('closed', 'Mumbai', 'Delhi', status: 'closed'),
        load('nowhere', 'Some village', 'Delhi'),
        load('own', 'Mumbai', 'Delhi'), // the trip's own load id
      ];
      final r = returnLoadsFor(trip(), loads.where((l) => l.id != 'own').followedBy([Load(
        id: 'own', shipperId: 'c', pickup: 'Mumbai', drop: 'Delhi', cargoType: 'x', weight: 1, vehicleType: '20ft', budget: 1, pickupDate: null, notes: '', status: 'open')]),
        excludeShipperId: 'me');
      expect(r.map((x) => x.load.id), ['home', 'near']);
      expect(r.first.towardsHome, isTrue);
      expect(r.last.towardsHome, isFalse);
      expect(returnLoadsFor(trip(drop: 'Some village'), loads), isEmpty);
    });

    test('a reminder tells the driver on the road that loads are waiting', () {
      final r = ReminderEngine.compute(ReminderInput(now: DateTime(2026, 10, 8), isDriver: true, bookings: [trip()], loads: [load('home', 'Mumbai', 'Delhi')]));
      expect(r.where((x) => x.kind == ReminderKind.returnLoads), hasLength(1));
      expect(r.firstWhere((x) => x.kind == ReminderKind.returnLoads).args, {'n': 1, 'city': 'Mumbai'});
      expect(ReminderEngine.compute(ReminderInput(now: DateTime(2026, 10, 8), isDriver: true, bookings: [trip(status: 'loading')], loads: [load('home', 'Mumbai', 'Delhi')])), isEmpty);
      expect(ReminderEngine.compute(ReminderInput(now: DateTime(2026, 10, 8), isDriver: true, bookings: [trip()], loads: [load('far', 'Chennai', 'Delhi')])), isEmpty);
    });

    testWidgets('the trip screen section lists them with the home run marked', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: ReturnLoadsSection(booking: trip(), loads: Stream.value([load('home', 'Mumbai', 'Delhi'), load('chn', 'Chennai', 'Delhi')]))))));
      await settle(tester);
      expect(find.text('Loads for the way back from Mumbai'), findsOneWidget);
      expect(find.byKey(const ValueKey('return_home')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_home')), findsOneWidget);
      expect(find.byKey(const ValueKey('return_chn')), findsNothing);
    });
  });

  group('screens', () {
    testWidgets('driver screen: post a truck, see it, close it, answer a request', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(driverWithVehicle);
      await tester.pumpWidget(app(const EmptyTrucksScreen()));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('truckFrom')), 'Pune');
      await tester.enterText(find.byKey(const ValueKey('truckTo')), 'Delhi');
      await tester.tap(find.byKey(const ValueKey('truckDate')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('truckPost')));
      await settle(tester);
      final posts = (await tester.runAsync(() => db.collection('truck_posts').get()))!.docs;
      expect(posts, hasLength(1));
      expect(posts.single.data()['fromCity'], 'Pune');

      await tester.runAsync(() => db.collection('truck_requests').doc('${posts.single.id}_c1').set({
            'postId': posts.single.id, 'driverId': 'd1', 'customerId': 'c1', 'customerName': 'Anil', 'pickup': 'Pune', 'drop': 'Delhi',
            'weight': 4, 'status': 'pending', 'createdAt': Timestamp.now(),
          }));
      await settle(tester);
      await tester.ensureVisible(find.byKey(ValueKey('accept_${posts.single.id}_c1')));
      await tester.tap(find.byKey(ValueKey('accept_${posts.single.id}_c1')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('truck_requests').doc('${posts.single.id}_c1').get()))!.data()!['status'], 'accepted');
      await tester.ensureVisible(find.byKey(ValueKey('closePost_${posts.single.id}')));
      await tester.tap(find.byKey(ValueKey('closePost_${posts.single.id}')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('truck_posts').doc(posts.single.id).get()))!.data()!['status'], 'closed');
    });

    testWidgets('customer board: filter the list and send a request', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final today = DateTime.now().add(const Duration(days: 2));
      final posts = [
        TruckPost(id: 'p1', driverId: 'd1', driverName: 'Ramesh', vehicleId: 'v', vehicleNumber: 'MH12AB1234', vehicleType: '20ft', capacity: 10, fromCity: 'Pune', toCity: 'Delhi', availableDate: today, status: 'open'),
        TruckPost(id: 'p2', driverId: 'd2', vehicleId: 'v2', vehicleNumber: 'KA01AB1', vehicleType: '14ft', capacity: 4, fromCity: 'Bengaluru', toCity: 'Chennai', availableDate: today, status: 'open'),
      ];
      uid = 'c1';
      await tester.runAsync(() => db.collection('truck_posts').doc('p1').set({'driverId': 'd1', 'status': 'open', 'vehicleType': '20ft', 'availableDate': Timestamp.fromDate(today)}));
      await tester.pumpWidget(app(TruckBoardScreen(posts: Stream.value(posts))));
      await settle(tester);
      expect(find.byKey(const ValueKey('truckPost_p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('truckPost_p2')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('boardFrom')), 'pune');
      await tester.pump();
      expect(find.byKey(const ValueKey('truckPost_p2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('request_p1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('reqWeight')), '6');
      await tester.tap(find.byKey(const ValueKey('reqSend')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('truck_requests').doc('p1_c1').get()))!.data()!['weight'], 6);
    });

    testWidgets('my requests: an accepted one offers the pre-filled load', (tester) async {
      uid = 'c1';
      await tester.runAsync(() => db.collection('truck_requests').doc('p1_c1').set({
            'postId': 'p1', 'driverId': 'd1', 'customerId': 'c1', 'pickup': 'Pune', 'drop': 'Delhi', 'weight': 6,
            'vehicleType': '20ft', 'status': 'accepted', 'createdAt': Timestamp.now(),
          }));
      await tester.pumpWidget(app(const MyTruckRequestsScreen()));
      await settle(tester);
      expect(find.text('Accepted'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('postFor_p1_c1')));
      await tester.pumpAndSettle();
      expect(find.text('Pune'), findsWidgets);
    });
  });
}
