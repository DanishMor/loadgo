import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/call/call_controller.dart';
import 'package:transport_app/core/call/call_models.dart';
import 'package:transport_app/core/call/call_provider.dart';
import 'package:transport_app/core/call/call_signaling.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/fleet.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/chat_service.dart';
import 'package:transport_app/core/services/comm_admin_service.dart';
import 'package:transport_app/core/services/comm_guard.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/transporter_service.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';

/// A call provider without a network: connects once both sides are set.
class _Phone implements CallProvider {
  final _cand = StreamController<CallCandidate>();
  final _conn = StreamController<bool>();
  @override
  bool get supported => true;
  @override
  Future<void> init() async {}
  @override
  Future<String> createOffer() async => 'v=0 offer from the caller side, long enough';
  @override
  Future<String> acceptOffer(String offerSdp) async {
    Future<void>.delayed(const Duration(milliseconds: 5), () => _conn.isClosed ? null : _conn.add(true));
    return 'v=0 answer from the callee side, long enough';
  }

  @override
  Future<void> setAnswer(String answerSdp) async => Future<void>.delayed(const Duration(milliseconds: 5), () => _conn.isClosed ? null : _conn.add(true));
  @override
  Future<void> addRemoteCandidate(CallCandidate c) async {}
  @override
  Stream<CallCandidate> get localCandidates => _cand.stream;
  @override
  Stream<bool> get connected => _conn.stream;
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setSpeaker(bool on) async {}
  @override
  Future<void> close() async {}
}

/// The whole story in one go: a transporter wins a load for the company,
/// assigns a driver, the customer and the driver talk, a phone number is
/// stopped and costs strikes up to a suspension, an admin lifts it, they call,
/// the trip is delivered, the transporter books it.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    await db.collection('users').doc('tr1').set({'role': 'fleet', 'companyName': 'Sharma Roadlines', 'fleet': {'pan': 'ABCDE1234F', 'officeCity': 'Indore'}, 'verified': true});
    await db.collection('users').doc('customer1').set({'role': 'customer', 'name': 'Anil', 'phone': '+919800000001'});
    await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh', 'phone': '+919800000002'});
    await db.collection('fleet_members').doc('tr1_d1').set({'ownerId': 'tr1', 'driverId': 'd1', 'driverName': 'Ramesh', 'active': true});
    await db.collection('vehicles').doc('tv1').set({'ownerId': 'tr1', 'number': 'MH12AB1111', 'type': '14ft', 'capacity': 10, 'status': 'active', 'availability': 'available'});
  });

  test('transporter wins, assigns; customer and driver chat and call without numbers; strikes; admin; delivery; books', () async {
    // 1. The customer posts a load; the transporter bids for the company; the customer picks it.
    uid = 'customer1';
    final loadId = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null, pickupDate: DateTime(2026, 10, 9), notes: '');
    uid = 'tr1';
    final load = Load.fromDoc(await db.collection('loads').doc(loadId).get());
    final vehicle = Vehicle.fromDoc(await db.collection('vehicles').doc('tv1').get());
    final offerId = await OfferService.send(load: load, vehicle: vehicle, pricePaise: 2400000, asCompany: true);
    uid = 'customer1';
    await OfferService.select(Offer.fromDoc(await db.collection('offers').doc(offerId).get()));
    uid = 'tr1';
    final bookingId = await OfferService.confirm(Offer.fromDoc(await db.collection('offers').doc(offerId).get()));
    var booking = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect(booking.isCompanyBooking, isTrue);
    expect(booking.driverPhone, '', reason: 'no phone number is stored on a booking');

    // 2. The transporter assigns a member driver; a stranger is refused.
    const member = FleetMember(id: 'tr1_d1', ownerId: 'tr1', driverId: 'd1', driverName: 'Ramesh', active: true);
    await expectLater(TransporterService.assign(booking: booking, vehicle: vehicle, driver: const FleetMember(id: 'x', ownerId: 'tr1', driverId: 'zz', active: false)), throwsA(isA<AssignException>()));
    await TransporterService.assign(booking: booking, vehicle: vehicle, driver: member);
    booking = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect(booking.runningDriverId, 'd1');

    // 3. Customer and driver chat; a phone number never goes through.
    uid = 'customer1';
    await ChatService.send(booking, 'Please call before reaching');
    uid = 'd1';
    await ChatService.send(booking, 'Sure, I will message from here');
    expect((await db.collection('bookings').doc(bookingId).collection('messages').get()).docs.length, 2);

    uid = 'customer1';
    Future<ViolationOutcome> tryNumber(String text) async {
      try {
        await ChatService.send(booking, text);
      } on ChatContactException catch (e) {
        return e.outcome;
      }
      fail('the message "$text" must be stopped');
    }

    expect((await tryNumber('call me on 9876543210')).warningOnly, isTrue);
    expect((await tryNumber('nau aath saat chhe paanch char teen do ek zero')).strikes, 2);
    final third = await tryNumber('my gpay ramesh@ybl');
    expect(third.strikes, 3);
    expect(third.blockedUntil, isNotNull);
    expect(third.blockedUntil!.difference(DateTime.now()).inHours, inInclusiveRange(23, 24));
    expect((await db.collection('bookings').doc(bookingId).collection('messages').get()).docs.length, 2, reason: 'none of the three was sent');
    expect((await db.collection('violations').get()).docs.length, 3);

    // 4. Suspended: no message, no call. The driver can still be reached by him.
    await expectLater(ChatService.send(booking, 'hello'), throwsA(isA<ChatBlockedException>()));
    final blockedCall = CallController(_Phone());
    await blockedCall.start(booking: booking, calleeId: 'd1', callerName: 'Anil');
    expect(blockedCall.endReason, CallEnd.blocked);

    // 5. An admin lifts the suspension and looks at the numbers (logged).
    uid = 'admin1';
    await CommAdminService.liftSuspension('customer1');
    final phones = await CommAdminService.revealPhones(['customer1', 'd1'], bookingId: bookingId);
    expect(phones['d1'], '+919800000002');
    expect((await db.collection('audit_events').where('type', isEqualTo: 'contact_view').get()).docs.length, 2);

    // 6. They call each other inside the app.
    uid = 'customer1';
    await ChatService.send(booking, 'Thanks, back in chat');
    final caller = CallController(_Phone());
    await caller.start(booking: booking, calleeId: callTarget(booking, 'customer1')!, callerName: 'Anil');
    expect(caller.phase, CallPhase.ringing);
    uid = 'd1';
    final ringing = (await CallSignaling.watchIncoming().first).single;
    expect(ringing.callerName, 'Anil');
    final callee = CallController(_Phone());
    await callee.answer(ringing);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect((caller.phase, callee.phase), (CallPhase.connected, CallPhase.connected));
    uid = 'customer1';
    await caller.hangUp();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(callee.phase, CallPhase.ended);

    // 7. The assigned driver delivers; the load closes; the transporter frees the vehicle and writes the books.
    uid = 'd1';
    for (final _ in [1, 2]) {
      await BookingService.advance(bookingId);
    }
    await BookingService.advance(bookingId, otp: '123456', pickup: const PickupProof(packages: 3, weightTons: 2));
    await BookingService.advance(bookingId);
    await BookingService.advance(bookingId);
    expect(await BookingService.advance(bookingId, otp: '123456', delivery: const DeliveryProof(receiverName: 'Anil')), BookingStatus.delivered);
    expect((await db.collection('loads').doc(loadId).get()).data()!['status'], LoadStatus.closed);

    uid = 'tr1';
    booking = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect(await TransporterService.releaseFinished([booking]), 1);
    await TransporterService.saveAccount(booking: booking, partyName: 'Anil Traders', revenuePaise: 2400000, driverPayPaise: 1800000, otherCostPaise: 100000, receivedPaise: 2400000);
    final books = TransporterBooks.from(await TransporterService.watchBooks().first);
    expect(books.marginPaise, 500000);
    expect(books.dueFromPartiesPaise, 0);
    expect((await db.collection('audit_events').where('type', isEqualTo: 'assign').get()).docs.length, 1);
  });
}
