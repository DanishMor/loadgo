import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/fleet.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/transporter_service.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/fleet/transporter_books_screen.dart';
import 'package:transport_app/fleet/transporter_shortcuts.dart';
import 'package:transport_app/fleet/transporter_trips_screen.dart';

import 'test_utils.dart';

const _gst = '27AAPFU0939F1ZV'; // a well-formed GSTIN with a correct check character

Vehicle veh(String id, {String owner = 'tr1', String? attachedTo, int cap = 10, Map<String, VehicleDocInfo> docs = const {}, String availability = 'available'}) =>
    Vehicle(id: id, ownerId: owner, number: 'MH12AB$id', type: '20ft', capacity: cap, rcNumber: 'R', status: 'active', attachedTo: attachedTo, docs: docs, availability: availability);

Booking company(String status, {String? driver, String? vehicle, num weight = 5, int paise = 2400000, Map<String, DateTime>? timeline}) => Booking(
      id: 'B1', loadId: 'L1', driverId: 'tr1', vehicleId: 'v1', customerId: 'c1', status: status, pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG',
      weight: weight, vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12ABv1', driverName: 'Sharma Roadlines', driverPhone: '',
      timeline: timeline ?? {status: DateTime(2026, 10, 8)}, fleetOwnerId: 'tr1', assignedDriverId: driver, assignedVehicleId: vehicle, agreedFarePaise: paise,
    );

FleetMember member(String id, {bool active = true}) => FleetMember(id: 'tr1_$id', ownerId: 'tr1', driverId: id, driverName: 'Driver $id', active: active);

void main() {
  group('profile', () {
    test('GST is optional but checked; PAN and city are required', () {
      const ok = TransporterProfile(company: 'Sharma Roadlines', gstin: _gst, pan: 'ABCDE1234F', officeCity: 'Indore', vehicleCount: 12);
      expect(ok.errors(), isEmpty);
      expect(const TransporterProfile(company: 'Sharma', pan: 'ABCDE1234F', officeCity: 'Indore').errors(), isEmpty, reason: 'no GST is fine');
      expect(TransporterProfile(company: 'Sharma', gstin: '27AAPFU0939F1ZX', pan: 'ABCDE1234F', officeCity: 'Indore').errors(), ['gstin'], reason: 'wrong check character');
      expect(const TransporterProfile(company: 'S', pan: 'BAD', officeCity: '', vehicleCount: -1).errors(), ['company', 'pan', 'city', 'vehicleCount']);
      expect(const TransporterProfile(company: 'Sharma', pan: 'ABCDE1234F', officeCity: 'Indore', vehicleCount: 100001).errors(), ['vehicleCount']);
    });

    test('routes are split, trimmed, de-duplicated and capped', () {
      expect(TransporterProfile.parseList(' Indore - Pune ,Delhi to Jaipur;\nindore - pune,, '), ['Indore - Pune', 'Delhi to Jaipur']);
      expect(TransporterProfile.parseList(List.generate(20, (i) => 'R$i').join(',')).length, TransporterProfile.maxRoutes);
      expect(TransporterProfile.parseList('x' * 61), isEmpty);
    });

    test('round trip through the users document; old documents need completion', () {
      const p = TransporterProfile(company: 'Sharma', gstin: _gst, pan: 'ABCDE1234F', officeCity: 'Indore', routes: ['A-B'], vehicleTypes: ['20ft'], vehicleCount: 3);
      final back = TransporterProfile.fromUser({'companyName': 'Sharma', 'business': {'gstin': _gst}, 'fleet': p.toFleetMap()});
      expect(back.officeCity, 'Indore');
      expect(back.routes, ['A-B']);
      expect(back.vehicleCount, 3);
      expect(back.gstin, _gst);
      final old = TransporterProfile.fromUser({'companyName': 'Old Co', 'fleet': {'pan': 'ABCDE1234F'}});
      expect(old.needsCompletion, isTrue);
      expect(TransporterProfile.fromUser(null).needsCompletion, isTrue);
    });

    test('the badge needs the fleet role and the admin approval', () {
      expect(isVerifiedTransporter({'role': 'fleet', 'verified': true}), isTrue);
      expect(isVerifiedTransporter({'role': 'fleet', 'verified': false}), isFalse);
      expect(isVerifiedTransporter({'role': 'driver', 'verified': true}), isFalse);
      expect(isVerifiedTransporter(null), isFalse);
    });

    test('the flag is registered and ON in pilot and normal mode', () {
      expect(const Features().isOn(FeatureKey.transporter), isTrue);
      expect(const Features(pilotMode: false).isOn(FeatureKey.transporter), isTrue);
      expect(const Features().withFlag(FeatureKey.transporter, false).isOn(FeatureKey.transporter), isFalse);
    });
  });

  group('document reminders', () {
    final now = DateTime(2026, 10, 8, 15);
    VehicleDocInfo exp(int days) => VehicleDocInfo(number: 'N', expiry: DateTime(2026, 10, 8).add(Duration(days: days)));

    test('expired first, then soonest; today still counts as valid; far ones are left out', () {
      final list = docReminders([
        veh('a', docs: {VehicleDocKind.insurance: exp(10), VehicleDocKind.puc: exp(90)}),
        veh('b', docs: {VehicleDocKind.permit: exp(-3), VehicleDocKind.fitness: exp(0)}),
      ], now);
      expect([for (final r in list) '${r.vehicle.id}.${r.kind}'], ['b.permit', 'b.fitness', 'a.insurance']);
      expect(list.first.expired, isTrue);
      expect(list[1].daysLeft, 0);
      expect(list[1].expired, isFalse);
    });

    test('inactive vehicles are skipped', () {
      final off = Vehicle(id: 'x', ownerId: 'tr1', number: 'MH12AB0000', type: '20ft', capacity: 5, rcNumber: 'R', status: 'inactive', docs: {VehicleDocKind.insurance: exp(-1)});
      expect(docReminders([off], now), isEmpty);
    });
  });

  group('assignment rules', () {
    final now = DateTime(2026, 10, 8);
    String? check({Booking? b, Vehicle? v, FleetMember? m}) =>
        assignmentProblem(booking: b ?? company(BookingStatus.accepted), transporterId: 'tr1', vehicle: v ?? veh('v2'), member: m ?? member('d1'), now: now);

    test('a valid pairing passes; an attached vehicle works too', () {
      expect(check(), isNull);
      expect(check(v: veh('v3', owner: 'd9', attachedTo: 'tr1')), isNull);
    });

    test('each refusal has its reason', () {
      expect(check(b: company(BookingStatus.pickedUp)), 'status');
      expect(check(b: company(BookingStatus.delivered)), 'status');
      expect(check(m: member('d1', active: false)), 'not_member');
      expect(assignmentProblem(booking: company(BookingStatus.accepted), transporterId: 'tr1', vehicle: veh('v2'), member: null, now: now), 'not_member');
      expect(check(v: veh('v4', owner: 'other')), 'vehicle');
      expect(check(v: veh('v4', owner: 'other', attachedTo: 'tr2')), 'vehicle');
      expect(check(v: veh('v2', availability: 'on_trip')), 'busy');
      expect(check(v: veh('v2', cap: 2)), 'capacity');
      expect(check(v: veh('v2', docs: {VehicleDocKind.insurance: VehicleDocInfo(number: 'N', expiry: DateTime(2026, 10, 1))})), 'papers');
      expect(check(b: company(BookingStatus.accepted, driver: 'd1', vehicle: 'v2'), v: veh('v2')), 'same');
    });

    test('the vehicle already on the booking may be kept while it is on its trip', () {
      expect(check(b: company(BookingStatus.accepted), v: veh('v1', availability: 'on_trip')), isNull);
    });

    test('someone else\'s booking cannot be assigned', () {
      final other = Booking.fromMap('B9', {'driverId': 'x', 'fleetOwnerId': 'tr2', 'status': 'accepted'});
      expect(check(b: other), 'status');
    });
  });

  group('delay alert', () {
    test('only trips on the road past the estimate and grace', () {
      final left = DateTime(2026, 10, 8, 6);
      final late = company(BookingStatus.inTransit, timeline: {BookingStatus.pickedUp: left});
      final onTime = company(BookingStatus.inTransit, timeline: {BookingStatus.pickedUp: DateTime(2026, 10, 8, 14)});
      final before = company(BookingStatus.accepted);
      // 200 km at 40 km/h = 5 h -> ETA 11:00; grace 60 min.
      final alerts = DelayAlert.compute([late, onTime, before], DateTime(2026, 10, 8, 13), (_) => 200);
      expect(alerts.length, 1);
      expect(alerts.single.minutesLate, 120);
      expect(DelayAlert.compute([late], DateTime(2026, 10, 8, 11, 30), (_) => 200), isEmpty, reason: 'inside the grace period');
      expect(DelayAlert.compute([late], DateTime(2026, 10, 8, 13), (_) => null), isEmpty, reason: 'no distance, no alert');
    });
  });

  group('books', () {
    test('rupees become integer paise, junk is refused', () {
      expect(TripAccount.paiseFromRupees('12,500'), 1250000);
      expect(TripAccount.paiseFromRupees('12500.5'), 1250050);
      expect(TripAccount.paiseFromRupees('12500.55'), 1250055);
      expect(TripAccount.paiseFromRupees(''), 0);
      expect(TripAccount.paiseFromRupees('-5'), isNull);
      expect(TripAccount.paiseFromRupees('1e5'), isNull);
      expect(TripAccount.paiseFromRupees('12.345'), isNull);
      expect(TripAccount.paiseFromRupees('1000001'), isNull, reason: 'above the 10 lakh rupee limit of the rules');
    });

    test('margin and what the party still owes', () {
      const a = TripAccount(bookingId: 'B1', partyId: 'c1', revenuePaise: 2400000, driverPayPaise: 1800000, otherCostPaise: 100000, receivedPaise: 500000);
      expect(a.marginPaise, 500000);
      expect(a.dueFromPartyPaise, 1900000);
      const over = TripAccount(bookingId: 'B2', partyId: 'c1', revenuePaise: 100, receivedPaise: 500);
      expect(over.dueFromPartyPaise, 0, reason: 'never negative');
      expect(const TripAccount(bookingId: 'B3', partyId: 'c1', revenuePaise: 100, driverPayPaise: 300).marginPaise, -200);
    });

    test('party-wise balance sums the trips and sorts the largest due first', () {
      final books = TransporterBooks.from(const [
        TripAccount(bookingId: 'B1', partyId: 'c1', partyName: 'Acme', revenuePaise: 1000000, driverPayPaise: 700000, receivedPaise: 400000),
        TripAccount(bookingId: 'B2', partyId: 'c1', revenuePaise: 500000, driverPayPaise: 300000, receivedPaise: 500000),
        TripAccount(bookingId: 'B3', partyId: 'c2', partyName: 'Zed', revenuePaise: 2000000, driverPayPaise: 1000000, otherCostPaise: 50000),
      ]);
      expect(books.revenuePaise, 3500000);
      expect(books.marginPaise, 3500000 - 2000000 - 50000);
      expect(books.dueFromPartiesPaise, 600000 + 2000000);
      expect([for (final p in books.parties) p.partyId], ['c2', 'c1']);
      expect(books.parties.last.trips, 2);
      expect(books.parties.last.partyName, 'Acme');
      expect(books.parties.last.duePaise, 600000);
      expect(TransporterBooks.from(const []).marginPaise, 0);
    });
  });

  group('services', () {
    late FakeFirebaseFirestore db;
    String? uid;

    setUp(() async {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => uid);
      languageNotifier.value = AppLanguage.english;
      await db.collection('users').doc('tr1').set({'role': 'fleet', 'companyName': 'Sharma Roadlines', 'name': 'Sunil', 'fleet': {'pan': 'ABCDE1234F'}});
      await db.collection('users').doc('c1').set({'role': 'customer', 'name': 'Anil'});
      await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh'});
      await db.collection('fleet_members').doc('tr1_d1').set({'ownerId': 'tr1', 'driverId': 'd1', 'driverName': 'Ramesh', 'active': true});
      await db.collection('vehicles').doc('tv1').set({'ownerId': 'tr1', 'number': 'MH12AB1111', 'type': '14ft', 'capacity': 10, 'status': 'active', 'availability': 'available'});
      await db.collection('vehicles').doc('tv2').set({'ownerId': 'tr1', 'number': 'MH12AB2222', 'type': '14ft', 'capacity': 10, 'status': 'active', 'availability': 'available'});
    });

    Future<Load> postLoad() async {
      final old = uid;
      uid = 'c1';
      final id = await LoadService.post(
          pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null, pickupDate: DateTime(2026, 10, 9), notes: '');
      uid = old;
      return Load.fromDoc(await db.collection('loads').doc(id).get());
    }

    Future<Vehicle> vehicle(String id) async => Vehicle.fromDoc(await db.collection('vehicles').doc(id).get());

    test('a load posted by a transporter carries the tag; a customer\'s does not', () async {
      uid = 'tr1';
      final id = await LoadService.post(
          pickup: 'Indore', drop: 'Pune', cargoType: 'Steel', weight: 8, vehicleType: '14ft', budget: null, pickupDate: DateTime(2026, 10, 9), notes: '');
      expect(Load.fromDoc(await db.collection('loads').doc(id).get()).postedByTransporter, isTrue);
      expect((await postLoad()).postedByTransporter, isFalse);
    });

    test('profile save: company, city, routes and the locked PAN', () async {
      uid = 'tr1';
      await TransporterService.updateProfile(const TransporterProfile(
          company: 'Sharma Roadways', gstin: _gst, pan: 'IGNORED1', officeCity: 'Indore', routes: ['Indore-Pune'], vehicleTypes: ['20ft'], vehicleCount: 12));
      final p = await TransporterService.loadProfile();
      expect(p.company, 'Sharma Roadways');
      expect(p.pan, 'ABCDE1234F', reason: 'the PAN cannot be edited here');
      expect(p.officeCity, 'Indore');
      expect(p.routes, ['Indore-Pune']);
      await expectLater(TransporterService.updateProfile(const TransporterProfile(company: 'X', officeCity: '')), throwsArgumentError);
    });

    test('company bid -> customer selects -> transporter confirms: a booking held by the company', () async {
      final load = await postLoad();
      uid = 'tr1';
      final id = await OfferService.send(load: load, vehicle: await vehicle('tv1'), pricePaise: 2400000, asCompany: true);
      final o = Offer.fromDoc(await db.collection('offers').doc(id).get());
      expect(o.isCompanyBid, isTrue);
      expect(o.fleetOwnerId, 'tr1');
      expect(o.driverName, 'Sharma Roadlines', reason: 'the customer sees the company, not a person');
      uid = 'c1';
      await OfferService.select(o);
      uid = 'tr1';
      final bookingId = await OfferService.confirm(Offer.fromDoc(await db.collection('offers').doc(id).get()));
      final b = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
      expect(b.fleetOwnerId, 'tr1');
      expect(b.isCompanyBooking, isTrue);
      expect(b.driverName, 'Sharma Roadlines');
      expect(b.agreedFarePaise, 2400000);
      expect(b.assignedDriverId, isNull);
      expect((await vehicle('tv1')).availability, VehicleAvailability.onTrip);
    });

    test('a normal driver offer is not a company bid and has no fleetOwnerId', () async {
      final load = await postLoad();
      uid = 'd1';
      await db.collection('vehicles').doc('dv1').set({'ownerId': 'd1', 'number': 'KA01CD5678', 'type': '14ft', 'capacity': 4, 'status': 'active', 'availability': 'available'});
      final id = await OfferService.send(load: load, vehicle: await vehicle('dv1'), pricePaise: 2500000);
      final raw = (await db.collection('offers').doc(id).get()).data()!;
      expect(raw.containsKey('fleetOwnerId'), isFalse);
      expect(raw['driverName'], 'Ramesh');
    });

    Future<String> wonBooking() async {
      final load = await postLoad();
      uid = 'tr1';
      final id = await OfferService.send(load: load, vehicle: await vehicle('tv1'), pricePaise: 2400000, asCompany: true);
      uid = 'c1';
      await OfferService.select(Offer.fromDoc(await db.collection('offers').doc(id).get()));
      uid = 'tr1';
      return OfferService.confirm(Offer.fromDoc(await db.collection('offers').doc(id).get()));
    }

    Future<Booking> booking(String id) async => Booking.fromDoc(await db.collection('bookings').doc(id).get());

    test('assign, then reassign: vehicles swap availability and every change is audited', () async {
      final bookingId = await wonBooking();
      final first = await booking(bookingId);
      await TransporterService.assign(booking: first, vehicle: await vehicle('tv1'), driver: member('d1'));
      var b = await booking(bookingId);
      expect(b.assignedDriverId, 'd1');
      expect(b.assignedVehicleNumber, 'MH12AB1111');
      expect(b.runningDriverId, 'd1');
      expect((await vehicle('tv1')).availability, VehicleAvailability.onTrip, reason: 'same vehicle, nothing freed');

      await db.collection('fleet_members').doc('tr1_d2').set({'ownerId': 'tr1', 'driverId': 'd2', 'driverName': 'Imran', 'active': true});
      await TransporterService.assign(booking: b, vehicle: await vehicle('tv2'), driver: member('d2'));
      b = await booking(bookingId);
      expect(b.assignedDriverId, 'd2');
      expect(b.assignedVehicleId, 'tv2');
      expect((await vehicle('tv1')).availability, VehicleAvailability.available);
      expect((await vehicle('tv2')).availability, VehicleAvailability.onTrip);

      final events = (await db.collection('audit_events').where('type', isEqualTo: 'assign').get()).docs.map((d) => d.data()).toList();
      expect(events.length, 2);
      expect(events.every((e) => e['actorId'] == 'tr1' && e['bookingId'] == bookingId), isTrue);
      expect(events.where((e) => e['data']['reassign'] == true).length, 1);
      expect(events.last['data'].containsKey('previousVehicleId'), isTrue);
    });

    test('a refused assignment writes nothing', () async {
      final bookingId = await wonBooking();
      final b = await booking(bookingId);
      await expectLater(TransporterService.assign(booking: b, vehicle: await vehicle('tv2'), driver: member('stranger', active: false)),
          throwsA(isA<AssignException>().having((e) => e.reason, 'reason', 'not_member')));
      expect((await booking(bookingId)).assignedDriverId, isNull);
      expect((await db.collection('audit_events').where('type', isEqualTo: 'assign').get()).docs, isEmpty);
    });

    test('attach and detach a vehicle; the transporter sees the attached ones', () async {
      await db.collection('vehicles').doc('dv1').set({'ownerId': 'd1', 'number': 'KA01CD5678', 'type': '14ft', 'capacity': 4, 'status': 'active', 'availability': 'available'});
      uid = 'd1';
      await TransporterService.setAttached('dv1', 'tr1');
      uid = 'tr1';
      expect([for (final v in await TransporterService.watchAttached().first) v.id], ['dv1']);
      uid = 'd1';
      await TransporterService.setAttached('dv1', null);
      uid = 'tr1';
      expect(await TransporterService.watchAttached().first, isEmpty);
    });

    test('books: create, update, the booking\'s customer is the party', () async {
      final bookingId = await wonBooking();
      final b = await booking(bookingId);
      await TransporterService.saveAccount(booking: b, partyName: 'Acme', revenuePaise: 2400000, driverPayPaise: 1800000, otherCostPaise: 0, receivedPaise: 0);
      await TransporterService.saveAccount(booking: b, partyName: 'Acme', revenuePaise: 2400000, driverPayPaise: 1800000, otherCostPaise: 50000, receivedPaise: 1000000);
      final books = TransporterBooks.from(await TransporterService.watchBooks().first);
      expect(books.accounts.length, 1);
      expect(books.parties.single.partyId, 'c1');
      expect(books.marginPaise, 550000);
      expect(books.dueFromPartiesPaise, 1400000);
      await expectLater(TransporterService.saveAccount(booking: b, revenuePaise: -1, driverPayPaise: 0, otherCostPaise: 0, receivedPaise: 0), throwsArgumentError);
      await expectLater(TransporterService.saveAccount(booking: b, revenuePaise: 100000001, driverPayPaise: 0, otherCostPaise: 0, receivedPaise: 0), throwsArgumentError);
    });
  });

  group('screens', () {
    Widget host(Widget child) => MaterialApp(
          home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: child)),
        );

    setUp(() => languageNotifier.value = AppLanguage.english);

    testWidgets('trips: not assigned warning, assign button, late alert and LR button', (tester) async {
      final left = DateTime(2026, 10, 8, 6);
      final late = company(BookingStatus.inTransit, timeline: {BookingStatus.pickedUp: left});
      final fresh = Booking.fromMap('B2', {
        'loadId': 'L2', 'driverId': 'tr1', 'vehicleId': 'v1', 'customerId': 'c1', 'status': 'accepted', 'pickup': 'Indore', 'drop': 'Pune', 'cargoType': 'x', 'weight': 3,
        'fleetOwnerId': 'tr1', 'timeline': {'accepted': Timestamp.fromDate(DateTime(2026, 10, 8))},
      });
      await tester.pumpWidget(host(TransporterTripsScreen(
        bookings: Stream.value([late, fresh]),
        offers: Stream.value(const []),
        members: Stream.value([member('d1')]),
        vehicles: () async => [veh('v2')],
        now: () => DateTime(2026, 10, 8, 23),
      )));
      await settle(tester);
      expect(find.byKey(const ValueKey('trpTrip_B1')), findsOneWidget);
      expect(find.byKey(const ValueKey('trpTrip_B2')), findsOneWidget);
      expect(find.byKey(const ValueKey('trpLate')), findsOneWidget);
      expect(find.byKey(const ValueKey('late_B1')), findsOneWidget);
      expect(find.textContaining('min late'), findsOneWidget);
      expect(find.byKey(const ValueKey('trpAssign_B2')), findsOneWidget);
      expect(find.byKey(const ValueKey('trpAssign_B1')), findsNothing, reason: 'on the road: it can no longer be changed');
      expect(find.text('Driver not assigned yet'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('trpLr_B2')), findsOneWidget);
    });

    testWidgets('trips: a selected company bid shows Confirm job', (tester) async {
      const o = Offer(id: 'L1_tr1', loadId: 'L1', driverId: 'tr1', customerId: 'c1', vehicleId: 'v1', vehicleNumber: 'MH12AB1111', vehicleType: '20ft', driverName: 'Sharma',
          pricePaise: 2400000, originalPaise: 2400000, status: OfferStatus.selected, fleetOwnerId: 'tr1', pickup: 'Delhi', drop: 'Jaipur');
      const plain = Offer(id: 'L2_tr1', loadId: 'L2', driverId: 'tr1', customerId: 'c1', vehicleId: 'v1', vehicleNumber: 'MH12AB1111', vehicleType: '20ft', driverName: 'S',
          pricePaise: 1, originalPaise: 1, status: OfferStatus.selected, pickup: 'X', drop: 'Y');
      await tester.pumpWidget(host(TransporterTripsScreen(bookings: Stream.value(const []), offers: Stream.value(const [o, plain]), members: Stream.value(const []))));
      await settle(tester);
      expect(find.byKey(const ValueKey('trpConfirm_L1_tr1')), findsOneWidget);
      expect(find.byKey(const ValueKey('trpConfirm_L2_tr1')), findsNothing, reason: 'only company bids are listed here');
    });

    testWidgets('books screen: totals and party-wise dues', (tester) async {
      await tester.pumpWidget(host(TransporterBooksScreen(accounts: Stream.value(const [
        TripAccount(bookingId: 'B1', partyId: 'c1', partyName: 'Acme', revenuePaise: 2400000, driverPayPaise: 1800000, receivedPaise: 400000),
        TripAccount(bookingId: 'B2', partyId: 'c2', partyName: 'Zed', revenuePaise: 100000, driverPayPaise: 20000, receivedPaise: 100000),
      ]))));
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('booksMargin'))).data, '₹ 6,800');
      expect(tester.widget<Text>(find.byKey(const ValueKey('partyDue_c1'))).data, '₹ 20,000');
      expect(tester.widget<Text>(find.byKey(const ValueKey('partyDue_c2'))).data, '₹ 0');
      expect(find.text('Acme'), findsOneWidget);
    });

    testWidgets('shortcuts: complete-profile card and expiring papers', (tester) async {
      await tester.pumpWidget(host(TransporterShortcuts(
        profile: () async => const TransporterProfile(company: 'Old Co'),
        vehicles: Stream.value([veh('a', docs: {VehicleDocKind.insurance: VehicleDocInfo(number: 'N', expiry: DateTime(2026, 10, 5))})]),
        now: () => DateTime(2026, 10, 8),
      )));
      await settle(tester);
      expect(find.byKey(const ValueKey('trpCompleteCard')), findsOneWidget);
      expect(find.byKey(const ValueKey('docReminder_a_insurance')), findsOneWidget);
      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('shortcuts: nothing extra when the profile is complete and papers are fine', (tester) async {
      await tester.pumpWidget(host(TransporterShortcuts(
        profile: () async => const TransporterProfile(company: 'Co', officeCity: 'Indore'),
        vehicles: Stream.value([veh('a')]),
        now: () => DateTime(2026, 10, 8),
      )));
      await settle(tester);
      expect(find.byKey(const ValueKey('trpCompleteCard')), findsNothing);
      expect(find.byKey(const ValueKey('trpDocReminders')), findsNothing);
      expect(find.byKey(const ValueKey('trpOpenBooks')), findsOneWidget);
    });
  });

  test('BookingService.accept without a company flag keeps the old fleetOwnerId rule', () async {
    final db = FakeFirebaseFirestore();
    String? uid = 'c1';
    Backend.useFakes(db: db, uid: () => uid);
    final id = await LoadService.post(pickup: 'A', drop: 'B', cargoType: 'x', weight: 1, vehicleType: '14ft', budget: null, pickupDate: DateTime(2026, 10, 9), notes: '');
    await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh'});
    await db.collection('vehicles').doc('fv').set({'ownerId': 'tr1', 'number': 'MH12AB3333', 'type': '14ft', 'capacity': 5, 'status': 'active', 'availability': 'available', 'assignedDriverId': 'd1'});
    uid = 'd1';
    final bid = await BookingService.accept(loadId: id, vehicle: Vehicle.fromDoc(await db.collection('vehicles').doc('fv').get()));
    final b = Booking.fromDoc(await db.collection('bookings').doc(bid).get());
    expect(b.fleetOwnerId, 'tr1');
    expect(b.isCompanyBooking, isFalse, reason: 'a member driver\'s own trip is not a company booking');
    expect(b.assignedDriverId, isNull);
  });
}
