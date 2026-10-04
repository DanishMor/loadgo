import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/identity/kyc_validators.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/driver_extras.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/models/user_settings.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/services/admin_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/driver_extras_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/notification_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/payment_service.dart';
import 'package:transport_app/core/services/payout_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/services/rating_service.dart';
import 'package:transport_app/core/services/rewards_service.dart';
import 'package:transport_app/core/services/settings_service.dart';
import 'package:transport_app/core/services/trip_evidence_service.dart';
import 'package:transport_app/core/services/trip_otp_service.dart';
import 'package:transport_app/core/services/user_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/models/trip_evidence.dart';
import 'package:transport_app/core/services/location_service.dart';

/// Integration-style flow on fake Firestore + mock Firebase Auth. There are
/// no security rules here (they are covered by firestore_rules_test); this
/// checks that the services hand the right data from one step to the next.
void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth current;
  final people = <String, MockFirebaseAuth>{};

  MockFirebaseAuth auth(String uid, String phone) =>
      people.putIfAbsent(uid, () => MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid, phoneNumber: phone)));

  void signInAs(String uid, String phone) => current = auth(uid, phone);

  setUp(() {
    db = FakeFirebaseFirestore();
    people.clear();
    signInAs('customer1', '+919800000001');
    Backend.useFakes(db: db, uid: () => current.currentUser?.uid, auth: () => current);
    PricingService.reset();
  });

  tearDown(() => LocationService.useFakeCurrent(null));

  test('customer to driver, bid, trip, delivery, rating, tip and payment', () async {
    // ---- admin sets up an offer (promo) and gives the customer some credits
    signInAs('admin1', '+919800000099');
    await RewardsService.savePromo(Promo(code: 'DIWALI10', type: Promo.percent, value: 10, maxDiscountPaise: 20000, expiresAt: DateTime(2030), usageLimit: 50, perUserLimit: 1));
    await RewardsService.grantCredits('customer1', 15000, note: 'welcome');

    // ---- customer: OTP login (role set once) -> profile
    signInAs('customer1', '+919800000001');
    await UserService.markRoleSelected('customer');
    expect(() => UserService.ensureRoleAllowed('customer', 'driver'), throwsA(isA<RoleMismatchException>()));
    await UserService.saveCustomerProfile(name: 'Anil Traders', companyName: 'Anil & Co', email: '', language: 'english', gstin: '27AAPFU0939F1ZV');
    var customer = (await db.collection('users').doc('customer1').get()).data()!;
    expect(customer['role'], 'customer');
    expect(customer['profileComplete'], true);
    expect(customer['phone'], '+919800000001');
    expect((customer['business'] as Map)['gstin'], '27AAPFU0939F1ZV');
    expect((await db.collection('identity_index').get()).docs, hasLength(1));

    // ---- customer posts a load with a promo, credits and two helpers
    const km = 270;
    final quote = PricingService.quote(vehicleType: '14ft', distanceKm: km, helpers: 2);
    expect(quote.helperCharge, 2 * PricingService.config.ruleFor('14ft', 'lcv').helperCharge);
    final promo = await RewardsService.reserve('diwali10', quote.total);
    expect(promo.discountPaise, (quote.total * 10 ~/ 100).clamp(0, 20000));
    final credits = (await RewardsService.balance()).clamp(0, quote.total - promo.discountPaise);
    final loadId = await LoadService.post(
      pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 3, vehicleType: '14ft', budget: null,
      pickupDate: DateTime.now().add(const Duration(days: 1)), notes: 'Handle with care', estimate: quote,
      helpers: 2, promo: promo, creditsUsedPaise: credits, fragile: true,
    );
    final load = Load.fromDoc(await db.collection('loads').doc(loadId).get());
    expect(load.helpers, 2);
    expect(load.promoCode, 'DIWALI10');
    expect(load.creditsUsedPaise, 15000);
    expect(load.fragile, isTrue);
    expect(await load.pickupGeohashPresent(db), isNotNull);
    expect(await RewardsService.balance(), 0, reason: 'credits were spent');

    // ---- driver: OTP login -> profile -> consent -> documents -> admin approval -> vehicle
    signInAs('driver1', '+919800000002');
    await UserService.markRoleSelected('driver');
    await UserService.saveDriverProfile(name: 'Ramesh', vehicleNumber: 'RJ14AB1234', vehicleType: '14ft', language: 'english');
    await SettingsService.answerLocationConsent(true);
    await UserService.saveDriverKyc(DriverKyc(dlNumber: 'RJ14 2015 0012345', dlExpiry: DateTime(2031), rcNumber: 'RJ14AB1234', aadhaarLast4: '4321', pan: 'ABCDE1234F'));
    var driver = (await db.collection('users').doc('driver1').get()).data()!;
    expect(driver['kycComplete'], true);
    expect(driver['verificationStatus'], 'pending');
    expect(Consents.fromMap(driver['consents']).location, isTrue);
    expect((await db.collection('identity_index').get()).docs, hasLength(4)); // GST + DL + PAN + RC

    signInAs('admin1', '+919800000099');
    await AdminService.setStatus('driver1', AdminService.approved);

    signInAs('driver1', '+919800000002');
    final vehicleId = await VehicleService.add(number: 'RJ14AB1234', type: '14ft', capacity: 4, rcNumber: 'RC-RJ14');
    final vehicle = (await VehicleService.fetchMyActive()).firstWhere((v) => v.id == vehicleId);

    // ---- driver bids; customer selects; driver confirms -> booking at the agreed price
    final openLoad = Load.fromDoc(await db.collection('loads').doc(loadId).get());
    final offerId = await OfferService.send(load: openLoad, vehicle: vehicle, pricePaise: 3200000);
    signInAs('customer1', '+919800000001');
    var offer = Offer.fromDoc(await db.collection('offers').doc(offerId).get());
    expect(offer.status, 'pending');
    await OfferService.select(offer);
    signInAs('driver1', '+919800000002');
    offer = Offer.fromDoc(await db.collection('offers').doc(offerId).get());
    expect(offer.status, 'selected');
    final bookingId = await OfferService.confirm(offer);
    var booking = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect(booking.agreedFarePaise, 3200000);
    expect(booking.helpers, 2);
    expect(booking.status, BookingStatus.accepted);
    expect(Load.fromDoc(await db.collection('loads').doc(loadId).get()).status, LoadStatus.matched);
    expect((await VehicleService.fetchMyActive()).single.availability, VehicleAvailability.onTrip);

    // ---- trip: customer creates the OTPs, driver runs the statuses
    signInAs('customer1', '+919800000001');
    final otps = await TripOtpService.ensure(bookingId);
    signInAs('driver1', '+919800000002');
    await BookingService.advance(bookingId); // driver_arriving
    await BookingService.advance(bookingId); // loading
    await TripEvidenceService.setOdometer(Booking.fromDoc(await db.collection('bookings').doc(bookingId).get()), start: true, km: 50000);
    await BookingService.startWaiting(Booking.fromDoc(await db.collection('bookings').doc(bookingId).get()));
    await BookingService.stopWaiting(Booking.fromDoc(await db.collection('bookings').doc(bookingId).get()), now: DateTime.now().add(const Duration(minutes: 20)));
    LocationService.useFakeCurrent(() async => (lat: 28.61, lng: 77.21));
    await BookingService.advance(bookingId, otp: otps.pickupOtp, pickup: const PickupProof(packages: 40, weightTons: 2.9)); // picked_up
    await TripEvidenceService.saveGps(bookingId, pickup: true);
    await BookingService.advance(bookingId); // in_transit
    await BookingService.advance(bookingId); // unloading
    final unloading = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    await TripEvidenceService.saveSignature(unloading, const SignatureStrokes([[(x: 0.1, y: 0.2), (x: 0.8, y: 0.7)]]));
    await TripEvidenceService.addCargoDoc(unloading, type: CargoDocType.invoice, number: 'INV-77');
    await BookingService.advance(bookingId, otp: otps.deliveryOtp, delivery: const DeliveryProof(receiverName: 'Suresh', receiverPhone: '9811111111')); // delivered
    await TripEvidenceService.saveGps(bookingId, pickup: false);
    await TripEvidenceService.setOdometer(Booking.fromDoc(await db.collection('bookings').doc(bookingId).get()), start: false, km: 50275);

    booking = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect(booking.status, BookingStatus.delivered);
    expect(booking.pickupOtpVerified && booking.deliveryOtpVerified, isTrue);
    expect(booking.deliveryProof!.receiverName, 'Suresh');
    expect(booking.pickupGps, isNotNull);
    expect(booking.deliveryGps, isNotNull);
    expect(booking.odometerEnd! - booking.odometerStart!, 275);
    expect(booking.detention.loadingMinutes, 20);
    expect(Load.fromDoc(await db.collection('loads').doc(loadId).get()).status, LoadStatus.closed);
    expect((await VehicleService.fetchMyActive()).single.availability, VehicleAvailability.available);
    expect(await TripEvidenceService.watchSignature(bookingId).first, isNotNull);
    expect(CargoDoc.latestByType(await TripEvidenceService.watchCargoDocs(bookingId).first)['invoice#0']!.number, 'INV-77');
    for (final s in [BookingStatus.accepted, BookingStatus.driverArriving, BookingStatus.loading, BookingStatus.pickedUp, BookingStatus.inTransit, BookingStatus.unloading, BookingStatus.delivered]) {
      expect(booking.timeline[s], isNotNull, reason: s);
    }

    // ---- both rate; customer tips; payment record; driver confirms
    await RatingService.rate(booking: booking, stars: 5, comment: 'On time');
    signInAs('customer1', '+919800000001');
    await RatingService.rate(booking: booking, stars: 4, comment: 'Careful driver');
    await DriverExtrasService.addTip(booking, 5000);
    await PaymentService.markPaid(booking, 3200000);
    signInAs('driver1', '+919800000002');
    booking = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect(booking.paymentStatus, PaymentStatus.customerMarkedPaid);
    await PaymentService.confirmReceived(booking);

    final summary = await RatingService.watchSummary('driver1').first;
    expect((summary.count, summary.average), (1, 4.0));
    expect(Tip.total(await DriverExtrasService.watchMyTips().first), 5000);
    final ledger = await PaymentService.watchLedger().first;
    expect(ledger.firstWhere((e) => e.type == 'trip_earning').amountPaise, 3200000);
    expect(ledger.firstWhere((e) => e.type == 'platform_commission').amountPaise, -160000, reason: '5% for a Free driver');

    // wallet: available now, a payout can be requested
    final bal = await PayoutService.balances();
    expect(bal.net, 3040000);
    expect(bal.pending, 0);
    final payoutId = await PayoutService.request(3000000);
    expect(Payout.fromDoc(payoutId, (await db.collection('payouts').doc(payoutId).get()).data()!).status, 'requested');

    // notifications reached the right people along the way
    final driverNotes = (await NotificationService.watchMine().first).map((n) => n.type).toSet();
    expect(driverNotes, containsAll(['rating_received', 'payment_marked']));
    signInAs('customer1', '+919800000001');
    final customerNotes = (await NotificationService.watchMine().first).map((n) => n.type).toSet();
    expect(customerNotes, containsAll(['load_accepted', 'status_changed', 'rating_received', 'payment_confirmed']));

    // audit trail has the verification and status changes
    final audit = (await db.collection('audit_events').get()).docs.map((d) => d.data()['type']).toSet();
    expect(audit, containsAll(['verification', 'accept', 'status_change']));
    expect(driver['role'], 'driver');
    expect(customer['role'], 'customer');
  });

  test('a second customer cannot reuse the first one\'s GST number or promo slot beyond the limit', () async {
    signInAs('admin1', '+919800000099');
    await RewardsService.savePromo(Promo(code: 'ONCE', type: Promo.flat, value: 5000, expiresAt: DateTime(2030), usageLimit: 1, perUserLimit: 1));
    signInAs('customer1', '+919800000001');
    await UserService.markRoleSelected('customer');
    await UserService.saveCustomerProfile(name: 'A', companyName: '', email: '', language: 'english', gstin: '27AAPFU0939F1ZV');
    final p = await RewardsService.reserve('ONCE', 100000);
    await LoadService.post(
      pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 1, vehicleType: '14ft', budget: null,
      pickupDate: DateTime.now().add(const Duration(days: 1)), notes: '', promo: p,
      estimate: PricingService.quote(vehicleType: '14ft', distanceKm: 100),
    );

    signInAs('customer2', '+919800000003');
    await UserService.markRoleSelected('customer');
    await expectLater(
      UserService.saveCustomerProfile(name: 'B', companyName: '', email: '', language: 'english', gstin: '27AAPFU0939F1ZV'),
      throwsA(anything),
      reason: 'GST already registered',
    );
    await expectLater(RewardsService.reserve('ONCE', 100000), throwsA(isA<PromoException>()), reason: 'the only slot is taken');
  });
}

extension on Load {
  /// The stored geohash for the pickup city (null when the pickup is unknown).
  Future<String?> pickupGeohashPresent(FirebaseFirestore db) async => (await db.collection('loads').doc(id).get()).data()?['pickupGeohash'] as String?;
}
