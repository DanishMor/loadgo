import 'package:cloud_firestore/cloud_firestore.dart';

/// This driver already has an offer on the load.
class OfferExistsException implements Exception {}

/// The price is outside 30%..300% of the load's fare estimate.
class OfferOutOfRangeException implements Exception {
  final int minPaise;
  final int maxPaise;
  final bool tooLow;
  OfferOutOfRangeException({required this.minPaise, required this.maxPaise, required this.tooLow});
}

/// The offer is no longer in a state that allows this action.
class OfferStateException implements Exception {}

/// Offer lifecycle. Must stay in sync with firestore.rules.
///
/// pending --customer counter--> countered --driver accepts--> pending (at the counter price)
/// pending --customer selects--> selected --driver confirms--> confirmed (booking created)
/// any open state --driver--> withdrawn; pending/selected --customer--> rejected
class OfferStatus {
  OfferStatus._();
  static const pending = 'pending';
  static const countered = 'countered';
  static const selected = 'selected';
  static const confirmed = 'confirmed';
  static const rejected = 'rejected';
  static const withdrawn = 'withdrawn';

  static const open = [pending, countered, selected];
}

/// `offers/{loadId}_{driverId}`: a driver's price for an open load.
class Offer {
  final String id;
  final String loadId;
  final String driverId;
  final String customerId;
  final String pickup;
  final String drop;
  final String vehicleId;
  final String vehicleNumber;
  final String vehicleType;
  final String driverName;

  /// Current price on the table (paise).
  final int pricePaise;

  /// The driver's first price, kept for history.
  final int originalPaise;

  /// Customer's single counter-offer (paise), if made.
  final int? counterPaise;
  final String status;
  final String? bookingId;
  final Timestamp? createdAt;

  /// Set on a company bid: the transporter who offers (equals [driverId]).
  final String? fleetOwnerId;

  const Offer({
    required this.id,
    required this.loadId,
    required this.driverId,
    required this.customerId,
    required this.vehicleId,
    this.pickup = '',
    this.drop = '',
    required this.vehicleNumber,
    required this.vehicleType,
    required this.driverName,
    required this.pricePaise,
    required this.originalPaise,
    required this.status,
    this.counterPaise,
    this.bookingId,
    this.createdAt,
    this.fleetOwnerId,
  });

  bool get isCompanyBid => fleetOwnerId != null;

  static String idFor(String loadId, String driverId) => '${loadId}_$driverId';

  bool get isOpen => OfferStatus.open.contains(status);

  /// The customer may counter once, while the offer is pending.
  bool get canCounter => status == OfferStatus.pending && counterPaise == null;

  factory Offer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Offer(
      id: doc.id,
      loadId: d['loadId'] as String? ?? '',
      driverId: d['driverId'] as String? ?? '',
      customerId: d['customerId'] as String? ?? '',
      pickup: d['pickup'] as String? ?? '',
      drop: d['drop'] as String? ?? '',
      vehicleId: d['vehicleId'] as String? ?? '',
      vehicleNumber: d['vehicleNumber'] as String? ?? '',
      vehicleType: d['vehicleType'] as String? ?? '',
      driverName: d['driverName'] as String? ?? '',
      pricePaise: (d['pricePaise'] as num?)?.round() ?? 0,
      originalPaise: (d['originalPaise'] as num?)?.round() ?? 0,
      counterPaise: (d['counterPaise'] as num?)?.round(),
      status: d['status'] as String? ?? OfferStatus.pending,
      bookingId: d['bookingId'] as String?,
      createdAt: d['createdAt'] as Timestamp?,
      fleetOwnerId: d['fleetOwnerId'] as String?,
    );
  }
}
