import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/cancel_reasons.dart';
import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/load.dart';
import '../models/paged.dart';
import '../models/app_notification.dart';
import '../models/offer.dart';
import '../models/vehicle.dart';
import 'pricing_service.dart';
import 'audit_service.dart';
import '../safety/trip_share_service.dart';
import 'backend.dart';
import 'server_clock.dart';
import '../documents/doc_expiry.dart';
import 'notification_service.dart';
import 'risk_service.dart';

/// Thrown when a load was taken by another driver, closed, or never existed.
class LoadUnavailableException implements Exception {
  @override
  String toString() => 'LoadUnavailableException';
}

/// Picking up / delivering needs the customer's OTP and the proof details.
class OtpRequiredException implements Exception {}

/// The rules rejected the OTP (it does not match the customer's code).
class WrongOtpException implements Exception {}

/// The driver's licence or the vehicle's insurance/permit/fitness paper is expired
/// (no admin override). [what] is 'licence' or 'vehicle'.
class DocsExpiredException implements Exception {
  final String what;
  DocsExpiredException(this.what);
  @override
  String toString() => 'DocsExpiredException($what)';
}

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
  ///
  /// [asCompany] (Task 67): a transporter books for the company; the
  /// booking then carries `fleetOwnerId` = the transporter, who assigns a
  /// driver afterwards.
  static Future<String> accept({required String loadId, required Vehicle vehicle, String? offerId, bool asCompany = false}) async {
    final uid = Backend.requireUid();
    await RiskService.ensureCanTransact();
    final profile = (await Backend.db.collection('users').doc(uid).get()).data() ?? const {};
    if (DocExpiry.licenceBlocked(profile, ServerClock.now())) throw DocsExpiredException('licence');
    final loadRef = Backend.db.collection('loads').doc(loadId);
    final bookingRef = _col.doc();

    try {
      await Backend.db.runTransaction((tx) async {
        final snap = await tx.get(loadRef);
        if (!snap.exists) throw LoadUnavailableException();
        final load = Load.fromDoc(snap);
        if (!load.isOpen || load.shipperId == uid || load.blocks(uid)) throw LoadUnavailableException();
        final vehicleRef = Backend.db.collection('vehicles').doc(vehicle.id);
        final vehicleSnap = await tx.get(vehicleRef);
        if (vehicleSnap.exists && Vehicle.fromDoc(vehicleSnap).papersBlocked(ServerClock.now())) throw DocsExpiredException('vehicle');
        if (vehicleSnap.exists && !Vehicle.fromDoc(vehicleSnap).canTakeBooking) throw VehicleBusyException();
        final rules = PricingService.config.schedule;
        final deferVehicle = load.scheduledAt != null && load.scheduledAt!.isAfter(ServerClock.now().add(Duration(minutes: rules.leadMinutes)));
        if (deferVehicle && await _vehicleHasClash(vehicle.id, load.scheduledAt!)) throw VehicleBusyException();
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
          if (load.scheduledAt != null) 'scheduledAt': Timestamp.fromDate(load.scheduledAt!),
          'bookingType': load.bookingType,
          'helpers': load.helpers,
          'rentalHours': ?load.rentalHours,
          if (load.containerNumber.isNotEmpty) 'containerNumber': load.containerNumber,
          if (load.sealNumber.isNotEmpty) 'sealNumber': load.sealNumber,
          'businessId': ?load.businessId,
          'costCenter': ?load.costCenter,
          'paymentMode': load.paymentMode,
          'paymentStatus': 'pending',
          'pickupDate': snap.data()!['pickupDate'],
          'notes': load.notes,
          'vehicleNumber': vehicle.number,
          'driverName': (asCompany ? profile['companyName'] : profile['driverName']) ?? '',
          // Phone numbers stay private (Task 68): chat and call happen inside the app.
          'driverPhone': '',
          if (asCompany) 'fleetOwnerId': uid else if (vehicle.ownerId != uid) 'fleetOwnerId': vehicle.ownerId,
          'timeline': {BookingStatus.accepted: FieldValue.serverTimestamp()},
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        // An advance booking does not block the vehicle until the driver starts it.
        if (vehicleSnap.exists && !deferVehicle) tx.update(vehicleRef, {'availability': VehicleAvailability.onTrip});
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
        AuditService.inTransaction(tx, AuditType.accept,
            targetId: load.shipperId, bookingId: bookingRef.id, loadId: load.id, data: {'vehicleId': vehicle.id});
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

  /// True when [vehicleId] already has an advance booking within 12 hours of
  /// [at] (client check only; the rules cannot see other bookings).
  static Future<bool> _vehicleHasClash(String vehicleId, DateTime at) async {
    final s = await _col.where('vehicleId', isEqualTo: vehicleId).get();
    for (final d in s.docs) {
      final b = Booking.fromDoc(d);
      if (b.status != BookingStatus.accepted || b.scheduledAt == null) continue;
      if (b.scheduledAt!.difference(at).abs() < const Duration(hours: 12)) return true;
    }
    return false;
  }

  /// Live single booking; emits null if it doesn't exist.
  /// Driver starts the waiting clock at the current stage (loading or
  /// unloading). Record only.
  static Future<void> startWaiting(Booking b) async {
    final stage = b.status;
    if (b.driverId != Backend.requireUid() || (stage != Detention.loadingStage && stage != Detention.unloadingStage)) {
      throw StateError('Waiting can only be recorded while loading or unloading');
    }
    if (b.detention.startedAt(stage) != null) return;
    await Backend.db.collection('bookings').doc(b.id).update({
      'detention.${stage}StartedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Driver stops the clock; the minutes waited are added to the stage.
  static Future<void> stopWaiting(Booking b, {DateTime? now}) async {
    final stage = b.status;
    final started = b.detention.startedAt(stage);
    if (b.driverId != Backend.requireUid() || started == null) throw StateError('Not waiting');
    final waited = (((now ?? ServerClock.now()).difference(started).inSeconds) / 60).ceil().clamp(0, Detention.maxMinutes);
    final total = (b.detention.minutes(stage) + waited).clamp(0, Detention.maxMinutes);
    await Backend.db.collection('bookings').doc(b.id).update({
      'detention.${stage}Minutes': total,
      'detention.${stage}StartedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

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
      final next = await _advance(ref, uid, otp: otp, pickup: pickup, delivery: delivery);
      TripShareService.syncStatus(bookingId, next);
      return next;
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
      // The booking holder, or the member driver a transporter assigned (Task 67).
      if (booking.driverId != uid && booking.assignedDriverId != uid) throw StateError('Only the assigned driver can update this booking');
      final holder = booking.driverId == uid;
      final next = booking.nextStatus;
      if (next == null) throw StateError('Booking already delivered');
      final otpOk = otp != null && RegExp(r'^\d{6}$').hasMatch(otp);
      if (next == BookingStatus.pickedUp && (!otpOk || pickup == null)) throw OtpRequiredException();
      if (next == BookingStatus.delivered && (!otpOk || delivery == null)) throw OtpRequiredException();
      // An assigned driver does not own the vehicle: the transporter frees it
      // (TransporterService.releaseFinished) when the trip is delivered.
      final freeVehicle = next == BookingStatus.delivered && holder ? await _freeVehicleLater(tx, booking.vehicleId) : () {};

      // Starting an advance booking is the moment the vehicle becomes busy.
      void Function()? markBusy;
      if (holder && booking.status == BookingStatus.accepted && booking.scheduledAt != null) {
        final vref = Backend.db.collection('vehicles').doc(booking.vehicleId);
        final vsnap = await tx.get(vref);
        if (vsnap.exists) {
          final av = vsnap.data()?['availability'] as String? ?? VehicleAvailability.available;
          if (av == VehicleAvailability.available) {
            markBusy = () => tx.update(vref, {'availability': VehicleAvailability.onTrip, 'updatedAt': FieldValue.serverTimestamp()});
          } else if (av != VehicleAvailability.onTrip) {
            throw VehicleBusyException();
          }
        }
      }

      markBusy?.call();
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
      AuditService.inTransaction(tx, AuditType.statusChange,
          targetId: booking.customerId, bookingId: booking.id, loadId: booking.loadId, data: {'from': booking.status, 'to': next});
      NotificationService.addInTransaction(
        tx,
        userId: booking.customerId,
        type: NotificationType.statusChanged,
        message: '${booking.pickup} → ${booking.drop}',
        relatedId: booking.id,
        status: next,
      );
      // The transporter who holds the booking hears about the assigned driver's steps too.
      if (!holder) {
        NotificationService.addInTransaction(
          tx,
          userId: booking.driverId,
          type: NotificationType.statusChanged,
          message: '${booking.pickup} → ${booking.drop}',
          relatedId: booking.id,
          status: next,
        );
      }
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
    if (booking.runningDriverId != uid || !(booking.isInTransit || booking.status == BookingStatus.driverArriving)) return;
    await ref.update({
      'lastKnownLocation': GeoPoint(lat, lng),
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// After a breakdown with a replacement requested: the driver moves the trip
  /// to [replacement] (their own or assigned vehicle that can carry the load).
  /// The new vehicle goes on_trip; the old one goes to maintenance when the
  /// driver owns it.
  static Future<void> replaceVehicle(Booking booking, Vehicle replacement, {Vehicle? old}) async {
    final uid = Backend.requireUid();
    if (booking.driverId != uid) throw StateError('not your trip');
    if (booking.breakdown?.replacementRequested != true) throw StateError('no replacement requested');
    if (!replacement.canTakeBooking || replacement.capacity < booking.weight || replacement.id == booking.vehicleId) {
      throw ArgumentError.value(replacement.id, 'replacement');
    }
    final db = Backend.db;
    final batch = db.batch();
    batch.update(_col.doc(booking.id), {
      'vehicleId': replacement.id,
      'vehicleNumber': replacement.number,
      'replacedVehicleIds': [...booking.replacedVehicleIds, booking.vehicleId],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(db.collection('vehicles').doc(replacement.id), {'availability': VehicleAvailability.onTrip, 'updatedAt': FieldValue.serverTimestamp()});
    if (old != null && old.ownerId == uid) {
      batch.update(db.collection('vehicles').doc(old.id), {'availability': VehicleAvailability.maintenance, 'updatedAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  /// Driver backs out of an accepted (not yet picked up) booking: the booking
  /// becomes cancelled, the load reopens for other drivers and the customer
  /// is notified.
  static Future<void> cancelByDriver(String bookingId, {String? reason}) async {
    if (!CancelReasons.valid('driver', reason)) throw ArgumentError.value(reason, 'reason');
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
        'cancellation': {'by': 'driver', 'chargePaise': cancellationCharge(booking, ServerClock.now()), 'reason': ?reason},
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
      RiskService.countCancel(tx);
      AuditService.inTransaction(tx, AuditType.cancel,
          targetId: booking.customerId, bookingId: booking.id, loadId: booking.loadId, data: {'by': 'driver', 'from': booking.status, 'reason': ?reason});
      NotificationService.addInTransaction(
        tx,
        userId: booking.customerId,
        type: NotificationType.bookingCancelled,
        message: '${booking.pickup} → ${booking.drop}',
        relatedId: booking.id,
      );
    });
    TripShareService.syncStatus(bookingId, BookingStatus.cancelled);
  }

  /// Customer cancels an advance booking the driver has not started. The
  /// load is closed as cancelled (not reopened). Returns the recorded charge
  /// (paise): free until the configured hours before pickup. Record only.
  static Future<int> cancelScheduledByCustomer(String bookingId, {DateTime? now, String? reason}) async {
    if (!CancelReasons.valid('customer', reason)) throw ArgumentError.value(reason, 'reason');
    final uid = Backend.requireUid();
    final ref = _col.doc(bookingId);
    final at = now ?? ServerClock.now();
    return Backend.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Booking not found');
      final booking = Booking.fromDoc(snap);
      if (booking.customerId != uid) throw StateError('Only the customer can cancel');
      if (!booking.canCustomerCancelScheduled) throw StateError('Only an advance booking that has not started can be cancelled');
      final charge = PricingService.config.cancellation.chargeForScheduled(
        now: at,
        scheduledAt: booking.scheduledAt!,
        farePaise: booking.agreedFarePaise ?? booking.fareEstimate,
      );
      final freeVehicle = await _freeVehicleLater(tx, booking.vehicleId);
      tx.update(ref, {
        'status': BookingStatus.cancelled,
        'timeline.${BookingStatus.cancelled}': FieldValue.serverTimestamp(),
        'cancellation': {'by': 'customer', 'chargePaise': charge, 'reason': ?reason},
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(Backend.db.collection('loads').doc(booking.loadId), {
        'status': LoadStatus.closed,
        'cancelled': true,
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      freeVehicle();
      RiskService.countCancel(tx);
      AuditService.inTransaction(tx, AuditType.cancel,
          targetId: booking.driverId, bookingId: booking.id, loadId: booking.loadId, data: {'by': 'customer', 'from': booking.status, 'reason': ?reason});
      NotificationService.addInTransaction(
        tx,
        userId: booking.driverId,
        type: NotificationType.bookingCancelled,
        message: '${booking.pickup} → ${booking.drop}',
        relatedId: booking.id,
      );
      return charge;
    });
  }

  /// Policy charge (paise) for cancelling [booking] at [now]. Recorded only.
  /// TODO(functions): compute server-side; rules only check the shape.
  static int cancellationCharge(Booking booking, DateTime now) {
    final accepted = booking.timeline[BookingStatus.accepted] ?? now;
    return PricingService.config.cancellation.chargeFor(elapsed: now.difference(accepted), farePaise: booking.agreedFarePaise ?? booking.fareEstimate);
  }

  /// Either party records the e-way bill number (12 digits, or empty to clear)
  /// and, optionally, the date it is valid until (at most a year ahead).
  static Future<void> setEwayBill(String bookingId, String number, {DateTime? validUntil, DateTime? now}) {
    final n = number.replaceAll(RegExp(r'\s'), '');
    if (n.isNotEmpty && !RegExp(r'^\d{12}$').hasMatch(n)) throw ArgumentError.value(number, 'number');
    if (validUntil != null && validUntil.isAfter((now ?? DateTime.now()).add(const Duration(days: 366)))) throw ArgumentError.value(validUntil, 'validUntil');
    return _col.doc(bookingId).update({
      'ewayBillNo': n,
      'ewayValidUntil': n.isEmpty || validUntil == null ? FieldValue.delete() : Timestamp.fromDate(validUntil),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
