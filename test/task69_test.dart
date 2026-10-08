import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/documents/payment_card.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/app_info.dart';
import 'package:transport_app/core/assistant/assistant_engine.dart';
import 'package:transport_app/core/call/call_controller.dart';
import 'package:transport_app/core/call/call_models.dart';
import 'package:transport_app/core/call/call_provider.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/fleet.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/settings/help_screen.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/chat_service.dart';
import 'package:transport_app/core/services/comm_guard.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/transporter_service.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/fleet/transporter_loads_screen.dart';
import 'package:transport_app/customer/customer_home_screen.dart';
import 'package:transport_app/driver/driver_trip_screen.dart';

import 'test_utils.dart';

/// Bug-hunt tests for the transporter and private-chat code (Phases 1-5).
/// A call provider that never connects (nobody picks up).
class _Quiet implements CallProvider {
  @override
  bool get supported => true;
  @override
  Future<void> init() async {}
  @override
  Future<String> createOffer() async => 'v=0 an offer that is long enough';
  @override
  Future<String> acceptOffer(String offerSdp) async => 'v=0';
  @override
  Future<void> setAnswer(String answerSdp) async {}
  @override
  Future<void> addRemoteCandidate(CallCandidate c) async {}
  @override
  Stream<CallCandidate> get localCandidates => const Stream.empty();
  @override
  Stream<bool> get connected => const Stream.empty();
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setSpeaker(bool on) async {}
  @override
  Future<void> close() async {}
}

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    await db.collection('users').doc('tr1').set({'role': 'fleet', 'companyName': 'Sharma Roadlines', 'fleet': {'pan': 'ABCDE1234F'}});
    await db.collection('users').doc('customer1').set({'role': 'customer', 'name': 'Anil'});
    await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh'});
    await db.collection('fleet_members').doc('tr1_d1').set({'ownerId': 'tr1', 'driverId': 'd1', 'driverName': 'Ramesh', 'active': true});
    await db.collection('vehicles').doc('tv1').set({'ownerId': 'tr1', 'number': 'MH12AB1111', 'type': '14ft', 'capacity': 10, 'status': 'active', 'availability': 'available'});
    await db.collection('vehicles').doc('tv2').set({'ownerId': 'tr1', 'number': 'MH12AB2222', 'type': '14ft', 'capacity': 10, 'status': 'active', 'availability': 'available'});
  });

  /// A load won by the company (bid, select, confirm) and assigned to d1 with tv1.
  Future<String> assignedBooking() async {
    uid = 'customer1';
    final lid = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null, pickupDate: DateTime(2026, 10, 9), notes: '');
    final load = Load.fromDoc(await db.collection('loads').doc(lid).get());
    uid = 'tr1';
    final v = Vehicle.fromDoc(await db.collection('vehicles').doc('tv1').get());
    final oid = await OfferService.send(load: load, vehicle: v, pricePaise: 2400000, asCompany: true);
    uid = 'customer1';
    await OfferService.select(Offer.fromDoc(await db.collection('offers').doc(oid).get()));
    uid = 'tr1';
    final bid = await OfferService.confirm(Offer.fromDoc(await db.collection('offers').doc(oid).get()));
    final b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
    await TransporterService.assign(booking: b, vehicle: v, driver: const FleetMember(id: 'tr1_d1', ownerId: 'tr1', driverId: 'd1', driverName: 'Ramesh', active: true));
    return bid;
  }

  group('the assigned driver runs the trip', () {
    test('steps through to delivery; the load closes; the vehicle stays with the transporter until released', () async {
      final bid = await assignedBooking();
      uid = 'd1';
      expect(await BookingService.advance(bid), BookingStatus.driverArriving);
      expect(await BookingService.advance(bid), BookingStatus.loading);
      expect(await BookingService.advance(bid, otp: '123456', pickup: const PickupProof(packages: 5, weightTons: 2)), BookingStatus.pickedUp);
      expect(await BookingService.advance(bid), BookingStatus.inTransit);
      expect(await BookingService.advance(bid), BookingStatus.unloading);
      expect(await BookingService.advance(bid, otp: '123456', delivery: const DeliveryProof(receiverName: 'Anil')), BookingStatus.delivered);
      final b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
      expect(b.driverId, 'tr1', reason: 'the transporter stays the holder');
      expect((await db.collection('loads').doc(b.loadId).get()).data()!['status'], LoadStatus.closed);
      expect((await db.collection('vehicles').doc('tv1').get()).data()!['availability'], 'on_trip', reason: 'the driver cannot free a vehicle that is not theirs');
      // The transporter's app frees it.
      uid = 'tr1';
      expect(await TransporterService.releaseFinished([b]), 1);
      expect((await db.collection('vehicles').doc('tv1').get()).data()!['availability'], 'available');
      expect(await TransporterService.releaseFinished([b]), 0, reason: 'nothing left to free');
    });

    test('a stranger cannot move the trip; the customer is told about each step', () async {
      final bid = await assignedBooking();
      uid = 'someone';
      await expectLater(BookingService.advance(bid), throwsA(isA<StateError>()));
      uid = 'd1';
      await BookingService.advance(bid);
      final notes = (await db.collection('notifications').where('userId', isEqualTo: 'customer1').get()).docs;
      expect(notes.any((n) => n.data()['type'] == 'status_changed'), isTrue);
    });

    test('a vehicle used by another running company trip is not freed', () async {
      final a = Booking.fromMap('A', {'driverId': 'tr1', 'fleetOwnerId': 'tr1', 'vehicleId': 'tv1', 'status': 'delivered', 'customerId': 'c'});
      final b = Booking.fromMap('B', {'driverId': 'tr1', 'fleetOwnerId': 'tr1', 'vehicleId': 'x', 'assignedVehicleId': 'tv1', 'status': 'in_transit', 'customerId': 'c'});
      await db.collection('vehicles').doc('tv1').update({'availability': 'on_trip'});
      uid = 'tr1';
      expect(await TransporterService.releaseFinished([a, b]), 0);
      expect((await db.collection('vehicles').doc('tv1').get()).data()!['availability'], 'on_trip');
    });

    test('someone else\'s vehicle is never touched by release', () async {
      await db.collection('vehicles').doc('other').set({'ownerId': 'zz', 'number': 'KA01CD0001', 'type': '14ft', 'capacity': 4, 'status': 'active', 'availability': 'on_trip'});
      final a = Booking.fromMap('A', {'driverId': 'tr1', 'fleetOwnerId': 'tr1', 'vehicleId': 'other', 'status': 'delivered', 'customerId': 'c'});
      uid = 'tr1';
      expect(await TransporterService.releaseFinished([a]), 0);
    });

    testWidgets('the trip screen of an assigned driver has no payment card, no cancel button', (tester) async {
      tester.view.physicalSize = const Size(800, 9000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bid = await assignedBooking();
      uid = 'd1';
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: DriverTripScreen(bookingId: bid))));
      await settle(tester);
      expect(find.byType(PaymentCard), findsNothing);
      expect(find.text('Cancel booking'), findsNothing);
      uid = 'tr1';
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: DriverTripScreen(bookingId: bid))));
      await settle(tester);
      expect(find.byType(PaymentCard), findsOneWidget, reason: 'the holder keeps the money part');
    });
  });

  group('loads that fit the transporter (LoadFit)', () {
    Load load(String id, String from, String to, {String type = '14ft'}) =>
        Load(id: id, shipperId: 'c', pickup: from, drop: to, cargoType: 'x', weight: 2, vehicleType: type, budget: null, pickupDate: null, notes: '', status: 'open');
    const profile = TransporterProfile(officeCity: 'Indore', routes: ['Indore - Pune', 'Delhi to Jaipur', 'Mumbai → Surat'], vehicleTypes: ['20ft']);

    test('route ends are read from dashes, "to" and arrows', () {
      expect(LoadFit.routeEnds('Indore - Pune'), ('indore', 'pune'));
      expect(LoadFit.routeEnds('Delhi to Jaipur'), ('delhi', 'jaipur'));
      expect(LoadFit.routeEnds('Mumbai → Surat'), ('mumbai', 'surat'));
      expect(LoadFit.routeEnds('Indore'), isNull);
      expect(LoadFit.routeEnds(''), isNull);
    });

    test('a load matches a route either way round, by city name inside the address', () {
      expect(LoadFit.onRoute(load('1', 'Indore, Madhya Pradesh', 'Pune, Maharashtra'), 'Indore - Pune'), isTrue);
      expect(LoadFit.onRoute(load('2', 'Pune', 'Indore'), 'Indore - Pune'), isTrue, reason: 'a return load');
      expect(LoadFit.onRoute(load('3', 'Indore', 'Nagpur'), 'Indore - Pune'), isFalse);
      expect(LoadFit.onRoute(load('4', 'Delhi', 'Jaipur'), 'Indore - Pune'), isFalse);
    });

    test('rank: route first, then vehicle type, then the office city; ties keep their order', () {
      final loads = [
        load('plain', 'Chennai', 'Madurai'),
        load('type', 'Chennai', 'Madurai', type: '20ft'),
        load('route', 'Delhi', 'Jaipur'),
        load('office', 'Indore', 'Nagpur'),
        load('plain2', 'Kochi', 'Madurai'),
      ];
      final ranked = LoadFit.rank(loads, profile);
      expect([for (final f in ranked) f.load.id], ['route', 'type', 'office', 'plain', 'plain2']);
      expect(ranked.first.route, isTrue);
      expect(ranked[1].vehicleType, isTrue);
      expect(ranked[2].nearOffice, isTrue);
    });

    test('an empty profile keeps the list as it is', () {
      final loads = [load('a', 'A', 'B'), load('b', 'C', 'D')];
      expect([for (final f in LoadFit.rank(loads, const TransporterProfile())) f.load.id], ['a', 'b']);
    });

    testWidgets('the loads tab marks loads on my routes and can show only those', (tester) async {
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(
          home: Scaffold(
            body: TransporterLoadsScreen(
              profile: () async => profile,
              loads: Stream.value([load('other', 'Chennai', 'Madurai'), load('mine', 'Delhi', 'Jaipur')]),
            ),
          ),
        ),
      ));
      await settle(tester);
      expect(find.byKey(const ValueKey('fitRoute_mine')), findsOneWidget);
      expect(find.byKey(const ValueKey('fitRoute_other')), findsNothing);
      final order = tester.getTopLeft(find.byKey(const ValueKey('trpLoad_mine'))).dy < tester.getTopLeft(find.byKey(const ValueKey('trpLoad_other'))).dy;
      expect(order, isTrue, reason: 'the load on my route is listed first');
      await tester.tap(find.byKey(const ValueKey('trpOnlyMine')));
      await settle(tester);
      expect(find.byKey(const ValueKey('trpLoad_mine')), findsOneWidget);
      expect(find.byKey(const ValueKey('trpLoad_other')), findsNothing);
    });
  });

  group('Sahayak and Help explain the private numbers', () {
    test('questions about numbers, WhatsApp and blocked messages get the contact answer', () {
      const engine = RuleEngine();
      for (final q in ['why can i not see driver number', 'phone number kyun nahi dikhta', 'my message blocked', 'driver ka number chahiye', 'call driver kaise', 'strike kya hai', 'फोन नंबर क्यों नहीं दिखता', 'whatsapp number do']) {
        expect(engine.reply(q, role: 'customer').intent, AssistantIntent.contactFaq, reason: q);
      }
      expect(engine.reply('how to pay', role: 'customer').intent, AssistantIntent.paymentFaq, reason: 'payment questions still go to payment');
      expect(engine.reply('what is otp', role: 'driver').intent, AssistantIntent.otpFaq);
      expect(T.get('asContact', AppLanguage.english), contains(AppInfo.name));
    });

    testWidgets('Help lists the new questions', (tester) async {
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: HelpScreen())));
      await settle(tester);
      for (var i = 9; i <= HelpScreen.faqCount; i++) {
        await tester.scrollUntilVisible(find.byKey(ValueKey('faq$i')), 200, scrollable: find.byType(Scrollable).first);
        expect(find.byKey(ValueKey('faq$i')), findsOneWidget);
      }
      expect(HelpScreen.faqCount, 11);
    });
  });

  group('notices', () {
    test('assigning tells the driver once; reassigning to the same driver does not repeat it', () async {
      final bid = await assignedBooking();
      final mine = (await db.collection('notifications').where('userId', isEqualTo: 'd1').get()).docs.where((n) => n.data()['type'] == 'trip_assigned').toList();
      expect(mine.length, 1);
      expect(mine.single.data()['relatedId'], bid);
      uid = 'tr1';
      final b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
      await TransporterService.assign(booking: b, vehicle: Vehicle.fromDoc(await db.collection('vehicles').doc('tv2').get()), driver: const FleetMember(id: 'tr1_d1', ownerId: 'tr1', driverId: 'd1', driverName: 'Ramesh', active: true));
      expect((await db.collection('notifications').where('userId', isEqualTo: 'd1').get()).docs.where((n) => n.data()['type'] == 'trip_assigned').length, 1);
    });

    test('the transporter hears about every step the assigned driver takes', () async {
      final bid = await assignedBooking();
      uid = 'd1';
      await BookingService.advance(bid);
      final holder = (await db.collection('notifications').where('userId', isEqualTo: 'tr1').get()).docs.map((n) => n.data()).where((n) => n['type'] == 'status_changed').toList();
      expect(holder.length, 1);
      expect(holder.single['status'], 'driver_arriving');
    });

    test('an unanswered call leaves one missed-call notice for the other person', () async {
      final bid = await assignedBooking();
      final b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
      uid = 'customer1';
      final c = CallController(_Quiet(), ringTimeout: const Duration(milliseconds: 40));
      await c.start(booking: b, calleeId: 'd1', callerName: 'Anil');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.endReason, CallEnd.noAnswer);
      final missed = (await db.collection('notifications').where('userId', isEqualTo: 'd1').get()).docs.where((n) => n.data()['type'] == 'missed_call').toList();
      expect(missed.length, 1);
      expect(missed.single.id, startsWith('missed_'));
    });
  });

  group('the Verified mark on a bid', () {
    test('only an admin-approved transporter\'s company bid carries it', () async {
      uid = 'customer1';
      final lid = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null, pickupDate: DateTime(2026, 10, 9), notes: '');
      final load = Load.fromDoc(await db.collection('loads').doc(lid).get());
      final v = Vehicle.fromDoc(await db.collection('vehicles').doc('tv1').get());
      uid = 'tr1';
      var oid = await OfferService.send(load: load, vehicle: v, pricePaise: 2400000, asCompany: true);
      expect(Offer.fromDoc(await db.collection('offers').doc(oid).get()).companyVerified, isFalse);
      await db.collection('offers').doc(oid).delete();
      await db.collection('users').doc('tr1').update({'verified': true});
      oid = await OfferService.send(load: load, vehicle: v, pricePaise: 2400000, asCompany: true);
      final o = Offer.fromDoc(await db.collection('offers').doc(oid).get());
      expect((o.isCompanyBid, o.companyVerified), (true, true));
    });
  });

  group('chat with a company booking', () {
    test('who is "the other person": the customer talks to the assigned driver, the driver to the customer', () async {
      final bid = await assignedBooking();
      final b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
      uid = 'customer1';
      expect(ChatService.otherParty(b), 'd1');
      uid = 'd1';
      expect(ChatService.otherParty(b), 'customer1');
      uid = 'tr1';
      expect(ChatService.otherParty(b), 'customer1');
      await ChatService.send(b, 'Truck is on the way');
      expect((await db.collection('notifications').where('userId', isEqualTo: 'customer1').get()).docs.any((n) => n.data()['type'] == 'chat_message'), isTrue);
    });

    test('a message from the assigned driver notifies the customer, not the transporter', () async {
      final bid = await assignedBooking();
      final b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
      uid = 'd1';
      await ChatService.send(b, 'Reached the gate');
      final forCustomer = (await db.collection('notifications').where('userId', isEqualTo: 'customer1').get()).docs.where((n) => n.data()['type'] == 'chat_message');
      final forTransporter = (await db.collection('notifications').where('userId', isEqualTo: 'tr1').get()).docs.where((n) => n.data()['type'] == 'chat_message');
      expect(forCustomer.length, 1);
      expect(forTransporter, isEmpty);
    });
  });

  group('old documents and empty data do not crash', () {
    test('a booking, vehicle, offer and user from before Task 67 and 68 read fine', () async {
      final b = Booking.fromMap('old', {'driverId': 'd', 'customerId': 'c', 'status': 'accepted'});
      expect((b.assignedDriverId, b.assignedVehicleId, b.assignedDriverName, b.isCompanyBooking, b.runningDriverId), (null, null, '', false, 'd'));
      await db.collection('vehicles').doc('old').set({'ownerId': 'x'});
      await db.collection('offers').doc('old').set({'driverId': 'x'});
      expect(Vehicle.fromDoc(await db.collection('vehicles').doc('old').get()).attachedTo, isNull);
      expect(Offer.fromDoc(await db.collection('offers').doc('old').get()).isCompanyBid, isFalse);
      uid = 'x';
      expect((await CommGuard.status()).strikes, 0);
      expect(CallDoc.fromMap('c', const {}).isLive, isFalse);
    });
  });

  testWidgets('customer Home has a "More for you" section with the screens that used to hide in Profile', (tester) async {
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'customer1', phoneNumber: '+919800000001'));
    Backend.useFakes(db: db, uid: () => 'customer1', auth: () => auth);
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: CustomerHomeScreen())));
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('homeMore_history')), 300, scrollable: find.byType(Scrollable).first);
    for (final id in ['history', 'templates', 'transactions', 'spending', 'drivers', 'analytics']) {
      expect(find.byKey(ValueKey('homeMore_$id'), skipOffstage: false), findsOneWidget, reason: id);
    }
    expect(find.text('More for you', skipOffstage: false), findsOneWidget);
  });
}
