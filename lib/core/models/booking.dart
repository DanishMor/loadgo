import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';

/// A driver's acceptance of a load. A load has at most one live booking at a
/// time (its `bookingId`); cancelled bookings stay as history.
class Booking {
  final String id;
  final String loadId;
  final String driverId;
  final String vehicleId;
  final String customerId;
  final String status;

  // Denormalized from the load/vehicle/driver so both parties can render the
  // booking without reading documents the rules keep private.
  final String pickup;
  final String drop;
  final String cargoType;
  final num weight;
  final String vehicleType;
  final num? budget;
  final DateTime? pickupDate;
  final String notes;
  final String vehicleNumber;
  final String driverName;
  final String driverPhone;

  /// Status -> time it was reached.
  final Map<String, DateTime> timeline;
  final Timestamp? createdAt;

  /// Driver's last shared position while the trip is in transit.
  final GeoPoint? lastKnownLocation;
  final DateTime? locationUpdatedAt;

  final List<String> extraPickups;
  final List<String> extraDrops;
  final String pickupSlot;

  /// Price agreed through an offer (paise), and that offer's id.
  final int? agreedFarePaise;
  final String? offerId;

  /// Load's estimated total (paise), copied at acceptance.
  final int? fareEstimate;

  /// Cargo details captured at pickup / receiver details at delivery.
  final PickupProof? pickupProof;
  final DeliveryProof? deliveryProof;

  /// True once the matching OTP was accepted (the rules check it).
  final bool pickupOtpVerified;
  final bool deliveryOtpVerified;

  /// Set when the driver reported a breakdown on this trip.
  final BookingBreakdown? breakdown;

  /// E-way bill number (12 digits), entered by either party.
  final String ewayBillNo;

  /// Digital LR / bilty number derived from the booking id.
  String get lrNumber => 'LG-${id.length > 10 ? id.substring(0, 10) : id}'.toUpperCase();

  /// Recorded when the booking is cancelled (no money moves).
  final BookingCancellation? cancellation;

  const Booking({
    required this.id,
    required this.loadId,
    required this.driverId,
    required this.vehicleId,
    required this.customerId,
    required this.status,
    required this.pickup,
    required this.drop,
    required this.cargoType,
    required this.weight,
    required this.vehicleType,
    required this.budget,
    required this.pickupDate,
    required this.notes,
    required this.vehicleNumber,
    required this.driverName,
    required this.driverPhone,
    required this.timeline,
    this.createdAt,
    this.lastKnownLocation,
    this.locationUpdatedAt,
    this.fareEstimate,
    this.agreedFarePaise,
    this.offerId,
    this.cancellation,
    this.pickupProof,
    this.deliveryProof,
    this.pickupOtpVerified = false,
    this.deliveryOtpVerified = false,
    this.ewayBillNo = '',
    this.breakdown,
    this.extraPickups = const [],
    this.extraDrops = const [],
    this.pickupSlot = PickupSlot.any,
  });

  List<String> get route => [pickup, ...extraPickups, ...extraDrops, drop];

  bool get isInTransit => status == BookingStatus.inTransit;

  bool get isActive => status != BookingStatus.delivered && status != BookingStatus.cancelled;

  /// Drivers may back out only until loading starts.
  bool get canDriverCancel => BookingStatus.driverCancellable.contains(status);
  String? get nextStatus => BookingStatus.next(status);

  factory Booking.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final rawTimeline = (d['timeline'] as Map?) ?? const {};
    return Booking(
      id: doc.id,
      loadId: d['loadId'] as String? ?? doc.id,
      driverId: d['driverId'] as String? ?? '',
      vehicleId: d['vehicleId'] as String? ?? '',
      customerId: d['customerId'] as String? ?? '',
      status: d['status'] as String? ?? BookingStatus.accepted,
      pickup: d['pickup'] as String? ?? '',
      drop: d['drop'] as String? ?? '',
      cargoType: d['cargoType'] as String? ?? '',
      weight: d['weight'] as num? ?? 0,
      vehicleType: d['vehicleType'] as String? ?? '',
      budget: d['budget'] as num?,
      pickupDate: (d['pickupDate'] as Timestamp?)?.toDate(),
      notes: d['notes'] as String? ?? '',
      vehicleNumber: d['vehicleNumber'] as String? ?? '',
      driverName: d['driverName'] as String? ?? '',
      driverPhone: d['driverPhone'] as String? ?? '',
      timeline: {
        for (final e in rawTimeline.entries)
          if (e.value is Timestamp) e.key.toString(): (e.value as Timestamp).toDate(),
      },
      createdAt: d['createdAt'] as Timestamp?,
      lastKnownLocation: d['lastKnownLocation'] as GeoPoint?,
      locationUpdatedAt: (d['locationUpdatedAt'] as Timestamp?)?.toDate(),
      fareEstimate: (d['fareEstimate'] as num?)?.round(),
      agreedFarePaise: (d['agreedFarePaise'] as num?)?.round(),
      offerId: d['offerId'] as String?,
      pickupProof: d['pickupProof'] is Map ? PickupProof.fromMap(Map<String, dynamic>.from(d['pickupProof'] as Map)) : null,
      deliveryProof:
          d['deliveryProof'] is Map ? DeliveryProof.fromMap(Map<String, dynamic>.from(d['deliveryProof'] as Map)) : null,
      pickupOtpVerified: d['pickupOtp'] is String,
      deliveryOtpVerified: d['deliveryOtp'] is String,
      ewayBillNo: d['ewayBillNo'] as String? ?? '',
      breakdown: d['breakdown'] is Map ? BookingBreakdown.fromMap(Map<String, dynamic>.from(d['breakdown'] as Map)) : null,
      extraPickups: [for (final s in (d['extraPickups'] as List?) ?? const []) s.toString()],
      extraDrops: [for (final s in (d['extraDrops'] as List?) ?? const []) s.toString()],
      pickupSlot: d['pickupSlot'] as String? ?? PickupSlot.any,
      cancellation: d['cancellation'] is Map ? BookingCancellation.fromMap(Map<String, dynamic>.from(d['cancellation'] as Map)) : null,
    );
  }
}

/// Breakdown reported by the driver; a replacement vehicle may be needed.
class BookingBreakdown {
  final String note;
  final bool replacementRequested;
  final DateTime? reportedAt;

  const BookingBreakdown({this.note = '', this.replacementRequested = true, this.reportedAt});

  factory BookingBreakdown.fromMap(Map<String, dynamic> m) => BookingBreakdown(
        note: m['note'] as String? ?? '',
        replacementRequested: m['replacementRequested'] != false,
        reportedAt: (m['reportedAt'] as Timestamp?)?.toDate(),
      );
}

/// What the driver records when loading is done (with the pickup OTP).
class PickupProof {
  final int packages;
  final num weightTons;
  final String sealNumber;
  final String damageNote;

  const PickupProof({required this.packages, required this.weightTons, this.sealNumber = '', this.damageNote = ''});

  factory PickupProof.fromMap(Map<String, dynamic> m) => PickupProof(
        packages: (m['packages'] as num?)?.round() ?? 0,
        weightTons: m['weightTons'] as num? ?? 0,
        sealNumber: m['sealNumber'] as String? ?? '',
        damageNote: m['damageNote'] as String? ?? '',
      );

  Map<String, Object> toMap() => {
        'packages': packages,
        'weightTons': weightTons,
        'sealNumber': sealNumber.trim(),
        'damageNote': damageNote.trim(),
      };
}

/// Receiver details recorded at delivery (with the delivery OTP).
class DeliveryProof {
  final String receiverName;
  final String receiverPhone;
  final String damageNote;

  const DeliveryProof({required this.receiverName, this.receiverPhone = '', this.damageNote = ''});

  factory DeliveryProof.fromMap(Map<String, dynamic> m) => DeliveryProof(
        receiverName: m['receiverName'] as String? ?? '',
        receiverPhone: m['receiverPhone'] as String? ?? '',
        damageNote: m['damageNote'] as String? ?? '',
      );

  Map<String, Object> toMap() => {
        'receiverName': receiverName.trim(),
        'receiverPhone': receiverPhone.trim(),
        'damageNote': damageNote.trim(),
      };
}

/// Who cancelled and the policy charge recorded for it (paise).
class BookingCancellation {
  final String by;
  final int chargePaise;

  const BookingCancellation({required this.by, required this.chargePaise});

  factory BookingCancellation.fromMap(Map<String, dynamic> m) =>
      BookingCancellation(by: m['by'] as String? ?? '', chargePaise: (m['chargePaise'] as num?)?.round() ?? 0);
}
