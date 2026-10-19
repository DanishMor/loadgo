import 'package:cloud_firestore/cloud_firestore.dart';

import '../dispatch/dispatch_models.dart';
import '../models/load.dart';
import 'server_clock.dart';
import '../pricing/offer_bounds.dart';
import '../models/offer.dart';
import '../models/vehicle.dart';
import 'analytics_events.dart';
import 'backend.dart';
import 'rate_limit_service.dart';
import 'risk_service.dart';
import 'funnel.dart';
import 'booking_service.dart';
import './safe_docs.dart';

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
  static Future<String> send({required Load load, required Vehicle vehicle, required int pricePaise, bool asCompany = false, int? etaMinutes, BidNote? note, int? pickupKm}) async {
    final uid = Backend.requireUid();
    if (!validPrice(pricePaise)) throw ArgumentError.value(pricePaise, 'pricePaise');
    _checkExtras(etaMinutes, pickupKm);
    if (!load.isOpen || load.shipperId == uid) throw OfferStateException();
    if (_windowClosed(load)) throw BidWindowClosedException();
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
        if (asCompany && profile['verified'] == true) 'companyVerified': true,
        'pricePaise': pricePaise,
        'originalPaise': pricePaise,
        'etaMinutes': ?etaMinutes,
        'pickupKm': ?pickupKm,
        if (note != null) 'noteChip': note.value,
        'status': OfferStatus.pending,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    if (asCompany) AnalyticsEvents.log(AnalyticsEvents.companyBid);
    Funnel.mark(FunnelStep.firstBid, role: asCompany ? 'fleet' : 'driver').ignore();
    return ref.id;
  }

  static void _checkExtras(int? etaMinutes, int? pickupKm) {
    if (etaMinutes != null && (etaMinutes < 1 || etaMinutes > 1440)) throw ArgumentError.value(etaMinutes, 'etaMinutes');
    if (pickupKm != null && (pickupKm < 0 || pickupKm > 3000)) throw ArgumentError.value(pickupKm, 'pickupKm');
  }

  /// A bid-mode load whose window has ended takes no new bids and no edits.
  static bool _windowClosed(Load load) => load.mode == LoadMode.bid && load.bidWindowEnds != null && !load.bidWindowEnds!.isAfter(ServerClock.now());

  /// The driver changes a pending bid once: a new price (inside 30% to 300% of the estimate), ETA or note. Then it is locked.
  static Future<void> edit(Offer offer, {required int pricePaise, int? etaMinutes, BidNote? note, int? pickupKm}) async {
    final uid = Backend.requireUid();
    if (offer.driverId != uid || offer.status != OfferStatus.pending) throw OfferStateException();
    if (offer.edited) throw BidAlreadyEditedException();
    if (!validPrice(pricePaise)) throw ArgumentError.value(pricePaise, 'pricePaise');
    _checkExtras(etaMinutes, pickupKm);
    final load = Load.fromDoc(await Backend.db.collection('loads').doc(offer.loadId).get());
    if (!load.isOpen) throw OfferStateException();
    if (_windowClosed(load)) throw BidWindowClosedException();
    final est = load.estimate?.total;
    final range = OfferBounds.check(pricePaise, est);
    if (range != null) throw OfferOutOfRangeException(minPaise: OfferBounds.minPaise(est!), maxPaise: OfferBounds.maxPaise(est), tooLow: range == 'low');
    await _transition(
      offer.id,
      (o) => o.status == OfferStatus.pending && !o.edited && o.driverId == uid,
      (_) => {'pricePaise': pricePaise, 'edited': true, 'etaMinutes': ?etaMinutes, 'pickupKm': ?pickupKm, if (note != null) 'noteChip': note.value},
    );
  }

  /// The customer accepts [offer]: it is selected and every other bid on the load that is still pending or selected is
  /// closed (rejected) in the same batch, so the driver is asked to confirm and nobody else keeps waiting.
  static Future<void> acceptBid(Offer offer, Iterable<Offer> others) async {
    final uid = Backend.requireUid();
    if (offer.customerId != uid || offer.status != OfferStatus.pending) throw OfferStateException();
    final batch = Backend.db.batch();
    for (final o in others) {
      if (o.id == offer.id || o.customerId != uid || o.loadId != offer.loadId) continue;
      if (o.status == OfferStatus.pending || o.status == OfferStatus.selected) {
        batch.update(_col.doc(o.id), {'status': OfferStatus.rejected, 'updatedAt': FieldValue.serverTimestamp()});
      }
    }
    batch.update(_col.doc(offer.id), {'status': OfferStatus.selected, 'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
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
      final list = s.docs.parse(Offer.fromDoc);
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
      final list = s.docs.parse(Offer.fromDoc);
      list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
      return list;
    });
  }

  /// The signed-in driver's offers, newest first.
  static Stream<List<Offer>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('driverId', isEqualTo: uid).snapshots().map((s) {
      final list = s.docs.parse(Offer.fromDoc);
      list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
      return list;
    });
  }
}
