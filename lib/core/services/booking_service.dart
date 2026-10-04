import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/load.dart';
import '../models/paged.dart';
import '../models/app_notification.dart';
import '../models/offer.dart';
import '../models/vehicle.dart';
import 'pricing_service.dart';
import 'backend.dart';
import 'notification_service.dart';

/// Thrown when a load was taken by another driver, closed, or never existed.
class LoadUnavailableException implements Exception {
  @override
  String toString() => 'LoadUnavailableException';
}

/// Picking up / delivering needs the customer's OTP and the proof details.
class OtpRequiredException implements Exception {}

/// The rules rejected the OTP (it does not match the customer's code).
class WrongOtpException implements Exception {}

/// The chosen vehicle is on another trip, in maintenance, suspended or off.
class VehicleBusyException implements Exception {
  @override
  String toString() => 'VehicleBusyException';
}

class BookingService {
  BookingService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      Backend.db.collection('bookings');

  /// Atomically books an open load for the signed-in driver.
  ///
  /// The load's open -> matched transition (checked in the transaction and by
  /// the rules) guarantees only one live booking per load. Returns the
  /// booking id.
  ///
  /// With [offerId] this is the driver's confirmation of a selected offer:
  /// the offer must still be selected and the booking carries its price as
  /// `agreedFarePaise`.
  static Future<String> accept({required String loadId, required Vehicle vehicle, String? offerId}) async {
    final uid = Backend.requireUid();
    final profile = (await Backend.db.collection('users').doc(uid).get()).data() ?? const {};
    final loadRef = Backend.db.collection('loads').doc(loadId);
    final bookingRef = _col.doc();

    try {
      await Backend.db.runTransaction((tx) async {
        final snap = await tx.get(loadRef);
        if (!snap.exists) throw LoadUnavailableException();
        final load = Load.fromDoc(snap);
        if (!load.isOpen || load.shipperId == uid) throw LoadUnavailableException();
        final vehicleRef = Backend.db.collection('vehicles').doc(vehicle.id);
        final vehicleSnap = await tx.get(vehicleRef);
        if (vehicleSnap.exists && !Vehicle.fromDoc(vehicleSnap).canTakeBooking) throw VehicleBusyException();
        final offerRef = offerId == null ? null : Backend.db.collection('offers').doc(offerId);
        final offer = offerRef == null ? null : Offer.fromDoc(await tx.get(offerRef));
        if (offer != null && (offer.status != OfferStatus.selected || offer.driverId != uid || offer.loadId != loadId)) {
          throw OfferStateException();
        }

        tx.set(bookingRef, {
          'loadId': load.id,
          'driverId': uid,
          'vehicleId': vehicle.id,
          'customerId': load.shipperId,
          'status': BookingStatus.accepted,
          'pickup': load.pickup,
          'drop': load.drop,
          'cargoType': load.cargoType,
          'weight': load.weight,
          'vehicleType': load.vehicleType,
          'budget': load.budget,
          'fareEstimate': ?load.estimate?.total,
          if (offer != null) 'offerId': offer.id,
          if (offer != null) 'agreedFarePaise': offer.pricePaise,
          if (load.extraPickups.isNotEmpty) 'extraPickups': load.extraPickups,
          if (load.extraDrops.isNotEmpty) 'extraDrops': load.extraDrops,
          'pickupSlot': load.pickupSlot,
          'pickupDate': snap.data()!['pickupDate'],
          'notes': load.notes,
          'vehicleNumber': vehicle.number,
          'driverName': profile['driverName'] ?? '',
          'driverPhone': profile['phone'] ?? '',
          'timeline': {BookingStatus.accepted: FieldValue.serverTimestamp()},
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (vehicleSnap.exists) tx.update(vehicleRef, {'availability': VehicleAvailability.onTrip});
        if (offerRef != null) {
          tx.update(offerRef, {
            'status': OfferStatus.confirmed,
            'bookingId': bookingRef.id,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        tx.update(loadRef, {
          'status': LoadStatus.matched,
          'driverId': uid,
          'bookingId': bookingRef.id,
          'matchedAt': FieldValue.serverTimestamp(),
        });
        NotificationService.addInTransaction(
          tx,
          userId: load.shipperId,
          type: NotificationType.loadAccepted,
          message: '${load.pickup} → ${load.drop}',
          relatedId: bookingRef.id,
        );
      });
    } on FirebaseException catch (e) {
      // Rules hide loads matched by other drivers, so a lost race surfaces as
      // permission-denied (or aborted under contention).
      if (e.code == 'permission-denied' || e.code == 'aborted' || e.code == 'not-found') {
        throw LoadUnavailableException();
      }
      rethrow;
    }
    return bookingRef.id;
  }

  /// Live single booking; emits null if it doesn't exist.
  static Stream<Booking?> watch(String bookingId) =>
      _col.doc(bookingId).snapshots().map((s) => s.exists ? Booking.fromDoc(s) : null);

  /// Moves the driver's booking to the next status in [BookingStatus.flow].
  /// Pickup needs [otp] + [pickup]; delivery needs [otp] + [delivery]
  /// (the rules compare the OTP with the customer's secret). Delivering also
  /// closes the load. Returns the new status.
  static Future<String> advance(String bookingId, {String? otp, PickupProof? pickup, DeliveryProof? delivery}) async {
    final uid = Backend.requireUid();
    final ref = _col.doc(bookingId);
    try {
      return await _advance(ref, uid, otp: otp, pickup: pickup, delivery: delivery);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' && otp != null) throw WrongOtpException();
      rethrow;
    }
  }

  static Future<String> _advance(DocumentReference<Map<String, dynamic>> ref, String uid,
      {String? otp, PickupProof? pickup, DeliveryProof? delivery}) {
    return Backend.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Booking not found');
      final booking = Booking.fromDoc(snap);
      if (booking.driverId != uid) throw StateError('Only the assigned driver can update this booking');
      final next = booking.nextStatus;
      if (next == null) throw StateError('Booking already delivered');
      final otpOk = otp != null && RegExp(r'^\d{6}$').hasMatch(otp);
      if (next == BookingStatus.pickedUp && (!otpOk || pickup == null)) throw OtpRequiredException();
      if (next == BookingStatus.delivered && (!otpOk || delivery == null)) throw OtpRequiredException();
      final freeVehicle = next == BookingStatus.delivered ? await _freeVehicleLater(tx, booking.vehicleId) : () {};

      tx.update(ref, {
        'status': next,
        'timeline.$next': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (next == BookingStatus.pickedUp) ...{'pickupOtp': otp, 'pickupProof': pickup!.toMap()},
        if (next == BookingStatus.delivered) ...{'deliveryOtp': otp, 'deliveryProof': delivery!.toMap()},
      });
      if (next == BookingStatus.delivered) {
        tx.update(Backend.db.collection('loads').doc(booking.loadId), {
          'status': LoadStatus.closed,
          'closedAt': FieldValue.serverTimestamp(),
        });
        freeVehicle();
      }
      NotificationService.addInTransaction(
        tx,
        userId: booking.customerId,
        type: NotificationType.statusChanged,
        message: '${booking.pickup} → ${booking.drop}',
        relatedId: booking.id,
        status: next,
      );
      return next;
    });
  }

  /// Driver shares their current position on an in-transit booking.
  static Future<void> updateLocation(String bookingId, double lat, double lng) async {
    final uid = Backend.requireUid();
    final ref = _col.doc(bookingId);
    final snap = await ref.get();
    if (!snap.exists) throw StateError('Booking not found');
    final booking = Booking.fromDoc(snap);
    if (booking.driverId != uid || !booking.isInTransit) return;
    await ref.update({
      'lastKnownLocation': GeoPoint(lat, lng),
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Driver backs out of an accepted (not yet picked up) booking: the booking
  /// becomes cancelled, the load reopens for other drivers and the customer
  /// is notified.
  static Future<void> cancelByDriver(String bookingId) async {
    final uid = Backend.requireUid();
    final ref = _col.doc(bookingId);
    await Backend.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Booking not found');
      final booking = Booking.fromDoc(snap);
      if (booking.driverId != uid) throw StateError('Only the assigned driver can cancel');
      if (!booking.canDriverCancel) throw StateError('Booking can no longer be cancelled');
      final freeVehicle = await _freeVehicleLater(tx, booking.vehicleId);

      tx.update(ref, {
        'status': BookingStatus.cancelled,
        'timeline.${BookingStatus.cancelled}': FieldValue.serverTimestamp(),
        'cancellation': {'by': 'driver', 'chargePaise': cancellationCharge(booking, DateTime.now())},
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(Backend.db.collection('loads').doc(booking.loadId), {
        'status': LoadStatus.open,
        'driverId': FieldValue.delete(),
        'bookingId': FieldValue.delete(),
        'matchedAt': FieldValue.delete(),
        'reopenedAt': FieldValue.serverTimestamp(),
      });
      freeVehicle();
      NotificationService.addInTransaction(
        tx,
        userId: booking.customerId,
        type: NotificationType.bookingCancelled,
        message: '${booking.pickup} → ${booking.drop}',
        relatedId: booking.id,
      );
    });
  }

  /// Policy charge (paise) for cancelling [booking] at [now]. Recorded only.
  /// TODO(functions): compute server-side; rules only check the shape.
  static int cancellationCharge(Booking booking, DateTime now) {
    final accepted = booking.timeline[BookingStatus.accepted] ?? now;
    return PricingService.config.cancellation.chargeFor(elapsed: now.difference(accepted), farePaise: booking.agreedFarePaise ?? booking.fareEstimate);
  }

  /// Either party records the e-way bill number (12 digits, or empty to clear).
  static Future<void> setEwayBill(String bookingId, String number) {
    final n = number.replaceAll(RegExp(r'\s'), '');
    if (n.isNotEmpty && !RegExp(r'^\d{12}$').hasMatch(n)) throw ArgumentError.value(number, 'number');
    return _col.doc(bookingId).update({'ewayBillNo': n, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Reads the booking's vehicle inside [tx] (reads must precede writes) and
  /// returns a write that frees it again, if it is still marked on_trip.
  static Future<void Function()> _freeVehicleLater(Transaction tx, String vehicleId) async {
    if (vehicleId.isEmpty) return () {};
    final ref = Backend.db.collection('vehicles').doc(vehicleId);
    final snap = await tx.get(ref);
    if (snap.data()?['availability'] != VehicleAvailability.onTrip) return () {};
    return () => tx.update(ref, {'availability': VehicleAvailability.available});
  }

  static Stream<List<Booking>> watchForDriver() => _watchWhere('driverId');

  static Stream<List<Booking>> watchForCustomer() => _watchWhere('customerId');

  static Stream<Paged<Booking>> watchForDriverPage(int limit) => _watchPage('driverId', limit);

  static Stream<Paged<Booking>> watchForCustomerPage(int limit) => _watchPage('customerId', limit);

  static Stream<Paged<Booking>> _watchPage(String field, int limit) {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const Paged.all([]));
    return newestPage(_col.where(field, isEqualTo: uid), limit).map((snap) {
      final list = snap.docs.map(Booking.fromDoc).toList();
      list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
      return Paged(list, hasMore: snap.docs.length >= limit);
    });
  }

  static Stream<List<Booking>> _watchWhere(String field) {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where(field, isEqualTo: uid).snapshots().map((snap) {
      final list = snap.docs.map(Booking.fromDoc).toList();
      list.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
      return list;
    });
  }
}
