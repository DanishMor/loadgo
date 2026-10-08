import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/load.dart';
import '../pricing/offer_bounds.dart';
import '../models/offer.dart';
import '../models/vehicle.dart';
import 'backend.dart';
import 'rate_limit_service.dart';
import 'risk_service.dart';
import 'booking_service.dart';

/// Price offers on open loads. Drivers offer, customers counter once and
/// select one, and the selected driver confirms, which creates the booking
/// (double confirmation). Firestore rules enforce every transition.
class OfferService {
  OfferService._();

  static const maxPaise = 100000000; // ₹10 lakh

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('offers');

  static bool validPrice(int paise) => paise > 0 && paise <= maxPaise;

  /// Driver offers [pricePaise] for [load] with [vehicle].
  ///
  /// With [asCompany] a transporter bids for the company (Task 67): the
  /// offer shows the company name, carries `fleetOwnerId`, and may use an
  /// attached vehicle. The vehicle and driver are assigned after winning.
  static Future<String> send({required Load load, required Vehicle vehicle, required int pricePaise, bool asCompany = false}) async {
    final uid = Backend.requireUid();
    if (!validPrice(pricePaise)) throw ArgumentError.value(pricePaise, 'pricePaise');
    if (!load.isOpen || load.shipperId == uid) throw OfferStateException();
    final est = load.estimate?.total;
    final range = OfferBounds.check(pricePaise, est);
    if (range != null) throw OfferOutOfRangeException(minPaise: OfferBounds.minPaise(est!), maxPaise: OfferBounds.maxPaise(est), tooLow: range == 'low');
    await RiskService.ensureCanTransact();
    final ref = _col.doc(Offer.idFor(load.id, uid));
    final profile = (await Backend.db.collection('users').doc(uid).get()).data() ?? const {};
    final rate = await RateLimit.prepare(RateLimit.offerKind, docId: ref.id);
    await Backend.db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) throw OfferExistsException();
      rate.addToTransaction(tx);
      tx.set(ref, {
        'loadId': load.id,
        'driverId': uid,
        'customerId': load.shipperId,
        'pickup': load.pickup,
        'drop': load.drop,
        'vehicleId': vehicle.id,
        'vehicleNumber': vehicle.number,
        'vehicleType': vehicle.type,
        'driverName': (asCompany ? profile['companyName'] : profile['driverName']) ?? '',
        if (asCompany) 'fleetOwnerId': uid,
        'pricePaise': pricePaise,
        'originalPaise': pricePaise,
        'status': OfferStatus.pending,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return ref.id;
  }

  static Future<void> _transition(String offerId, bool Function(Offer o) allowed, Map<String, Object?> Function(Offer o) data) {
    final ref = _col.doc(offerId);
    return Backend.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw OfferStateException();
      final o = Offer.fromDoc(snap);
      if (!allowed(o)) throw OfferStateException();
      tx.update(ref, {...data(o), 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  /// Driver takes the offer back.
  static Future<void> withdraw(String offerId) =>
      _transition(offerId, (o) => o.isOpen && o.driverId == Backend.uid, (_) => {'status': OfferStatus.withdrawn});

  /// Driver agrees to the customer's counter price.
  static Future<void> acceptCounter(String offerId) => _transition(
        offerId,
        (o) => o.status == OfferStatus.countered && o.driverId == Backend.uid,
        (o) => {'status': OfferStatus.pending, 'pricePaise': o.counterPaise},
      );

  /// Customer's one counter-offer.
  static Future<void> counter(String offerId, int paise) {
    if (!validPrice(paise)) throw ArgumentError.value(paise, 'paise');
    return _transition(
      offerId,
      (o) => o.canCounter && o.customerId == Backend.uid,
      (_) => {'status': OfferStatus.countered, 'counterPaise': paise},
    );
  }

  static Future<void> reject(String offerId) => _transition(
        offerId,
        (o) => (o.status == OfferStatus.pending || o.status == OfferStatus.selected) && o.customerId == Backend.uid,
        (_) => {'status': OfferStatus.rejected},
      );

  /// Customer picks [offer]; any previously selected offer on the load goes
  /// back to pending so only one driver is asked to confirm.
  static Future<void> select(Offer offer) async {
    final uid = Backend.requireUid();
    if (offer.customerId != uid || offer.status != OfferStatus.pending) throw OfferStateException();
    final previous = await _col
        .where('loadId', isEqualTo: offer.loadId)
        .where('customerId', isEqualTo: uid)
        .where('status', isEqualTo: OfferStatus.selected)
        .get();
    final batch = Backend.db.batch();
    for (final d in previous.docs) {
      batch.update(d.reference, {'status': OfferStatus.pending, 'updatedAt': FieldValue.serverTimestamp()});
    }
    batch.update(_col.doc(offer.id), {'status': OfferStatus.selected, 'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  /// Selected driver confirms: the booking is created at the agreed price in
  /// the same transaction as the load match. Returns the booking id.
  static Future<String> confirm(Offer offer) async {
    if (offer.driverId != Backend.requireUid() || offer.status != OfferStatus.selected) throw OfferStateException();
    final vehicle = Vehicle.fromDoc(await Backend.db.collection('vehicles').doc(offer.vehicleId).get());
    return BookingService.accept(loadId: offer.loadId, vehicle: vehicle, offerId: offer.id, asCompany: offer.isCompanyBid);
  }

  /// Offers on one of the customer's loads, best price first.
  static Stream<List<Offer>> watchForLoad(String loadId) {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('loadId', isEqualTo: loadId).where('customerId', isEqualTo: uid).snapshots().map((s) {
      final list = s.docs.map(Offer.fromDoc).toList();
      list.sort((a, b) {
        final open = (b.isOpen ? 1 : 0) - (a.isOpen ? 1 : 0);
        return open != 0 ? open : a.pricePaise.compareTo(b.pricePaise);
      });
      return list;
    });
  }

  /// Offers made on any of the signed-in customer's loads, newest first.
  static Stream<List<Offer>> watchForCustomer() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('customerId', isEqualTo: uid).snapshots().map((s) {
      final list = s.docs.map(Offer.fromDoc).toList();
      list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
      return list;
    });
  }

  /// The signed-in driver's offers, newest first.
  static Stream<List<Offer>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('driverId', isEqualTo: uid).snapshots().map((s) {
      final list = s.docs.map(Offer.fromDoc).toList();
      list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
      return list;
    });
  }
}
