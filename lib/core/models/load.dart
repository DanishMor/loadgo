import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../pricing/fare_calculator.dart';

/// Who may see and accept a load. `favourites` and `invite` copy the allowed
/// driver ids onto the load (`allowedDriverIds`); the rules refuse anyone else.
class LoadVisibility {
  LoadVisibility._();
  static const public = 'public';
  static const favourites = 'favourites';
  static const invite = 'invite';
  static const all = [public, favourites, invite];
  static const maxAllowed = 20;
}

class Load {
  final String id;
  final String shipperId;
  final String pickup;
  final String drop;
  final String cargoType;
  final num weight;
  final String vehicleType;
  final num? budget;
  final DateTime? pickupDate;
  final String notes;
  final String status;

  /// True when the shipper cancelled the load (status is then `closed`).
  final bool cancelled;
  final String? driverId;
  final String? bookingId;
  final Timestamp? createdAt;

  /// Fare estimate shown when posting (paise); null for older loads.
  final FareBreakdown? estimate;

  /// [DistanceSource] of [estimate].
  final String? distanceSource;

  /// Pickups after [pickup] and drops before [drop], in visiting order
  /// (at most [maxStopsPerSide] - 1 each).
  final List<String> extraPickups;
  final List<String> extraDrops;

  /// [PickupSlot] value.
  final String pickupSlot;

  /// `PaymentMode` value (cash / upi_direct).
  final String paymentMode;

  /// Import/export details and the business branch the load starts from.
  final String containerNumber;
  final String sealNumber;
  final String? branchId;

  /// Set when the load is one leg of a two-leg shipment.
  final String? shipmentId;
  final int? shipmentLeg;

  /// [BookingType] value; helpers (0-4) apply to every type.
  final String bookingType;
  final int helpers;

  /// 4, 8 or 12 for hourly rentals.
  final int? rentalHours;

  /// Packers-and-movers request (items, floor, lift, packing).
  final MoversDetails? movers;

  /// Driver this load was posted for (from an accepted truck request). A
  /// hint only: any verified driver can still accept.
  final String? invitedDriverId;

  /// Company account this load is booked under (the owner's uid) and the
  /// internal cost centre tag, for the business statement.
  final String? businessId;
  final String? costCenter;

  /// Drivers the customer had blocked when posting. They do not see the load
  /// and cannot accept it.
  final List<String> blockedDriverIds;

  /// [LoadVisibility] value and, when not public, the drivers who may accept.
  final String visibility;
  final List<String> allowedDriverIds;

  /// "Pickup now": wanted within the hour (drivers see a chip, ranked first).
  final bool instant;

  /// `fleet` when a transporter posted the load (shown as "Posted by transporter").
  final String? postedByRole;
  bool get postedByTransporter => postedByRole == 'fleet';

  /// Exact pickup time for an advance booking (null = no fixed time).
  final DateTime? scheduledAt;

  /// Handle with care / valuable goods (shown to drivers before accepting).
  final bool fragile;
  final bool highValue;

  /// Value of the goods the customer declared (paise), for claims. Optional.
  final int? declaredValuePaise;

  /// Why the customer cancelled this load (code from CancelReasons), if said.
  final String? cancelReason;

  /// Promo applied at posting (record only) and credits spent, in paise.
  final String? promoCode;
  final int promoDiscountPaise;
  final int creditsUsedPaise;

  const Load({
    required this.id,
    required this.shipperId,
    required this.pickup,
    required this.drop,
    required this.cargoType,
    required this.weight,
    required this.vehicleType,
    required this.budget,
    required this.pickupDate,
    required this.notes,
    required this.status,
    this.cancelled = false,
    this.driverId,
    this.bookingId,
    this.createdAt,
    this.estimate,
    this.distanceSource,
    this.extraPickups = const [],
    this.extraDrops = const [],
    this.pickupSlot = PickupSlot.any,
    this.paymentMode = 'cash',
    this.containerNumber = '',
    this.sealNumber = '',
    this.branchId,
    this.shipmentId,
    this.shipmentLeg,
    this.bookingType = BookingType.freight,
    this.helpers = 0,
    this.rentalHours,
    this.movers,
    this.scheduledAt,
    this.invitedDriverId,
    this.businessId,
    this.costCenter,
    this.blockedDriverIds = const [],
    this.visibility = LoadVisibility.public,
    this.allowedDriverIds = const [],
    this.instant = false,
    this.postedByRole,
    this.fragile = false,
    this.highValue = false,
    this.declaredValuePaise,
    this.cancelReason,
    this.promoCode,
    this.promoDiscountPaise = 0,
    this.creditsUsedPaise = 0,
  });

  bool get isOpen => status == LoadStatus.open;

  /// True when [driverId] is on this load's block list.
  bool blocks(String? driverId) => driverId != null && (blockedDriverIds.contains(driverId) || !allows(driverId));

  /// False when the load is limited to chosen drivers and [driverId] is not one.
  bool allows(String? driverId) => visibility == LoadVisibility.public || (driverId != null && allowedDriverIds.contains(driverId));

  /// Every stop in visiting order: pickups, extra drops, final drop.
  List<String> get route => [pickup, ...extraPickups, ...extraDrops, drop];

  int get extraStopCount => extraPickups.length + extraDrops.length;

  factory Load.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Load(
      id: doc.id,
      shipperId: d['shipperId'] as String? ?? '',
      pickup: d['pickup'] as String? ?? '',
      drop: d['drop'] as String? ?? '',
      cargoType: d['cargoType'] as String? ?? '',
      weight: d['weight'] as num? ?? 0,
      vehicleType: d['vehicleType'] as String? ?? '',
      budget: d['budget'] as num?,
      pickupDate: (d['pickupDate'] as Timestamp?)?.toDate(),
      notes: d['notes'] as String? ?? '',
      status: d['status'] as String? ?? LoadStatus.open,
      cancelled: d['cancelled'] == true,
      driverId: d['driverId'] as String?,
      bookingId: d['bookingId'] as String?,
      createdAt: d['createdAt'] as Timestamp?,
      estimate: d['estimate'] is Map ? FareBreakdown.fromMap(Map<String, dynamic>.from(d['estimate'] as Map)) : null,
      distanceSource: (d['estimate'] as Map?)?['distanceSource'] as String?,
      extraPickups: [for (final s in (d['extraPickups'] as List?) ?? const []) s.toString()],
      extraDrops: [for (final s in (d['extraDrops'] as List?) ?? const []) s.toString()],
      pickupSlot: d['pickupSlot'] as String? ?? PickupSlot.any,
      paymentMode: d['paymentMode'] as String? ?? 'cash',
      containerNumber: d['containerNumber'] as String? ?? '',
      sealNumber: d['sealNumber'] as String? ?? '',
      branchId: d['branchId'] as String?,
      shipmentId: d['shipmentId'] as String?,
      shipmentLeg: (d['shipmentLeg'] as num?)?.toInt(),
      bookingType: d['bookingType'] as String? ?? BookingType.freight,
      helpers: (d['helpers'] as num?)?.toInt() ?? 0,
      rentalHours: (d['rentalHours'] as num?)?.toInt(),
      movers: d['movers'] is Map ? MoversDetails.fromMap(d['movers']) : null,
      scheduledAt: (d['scheduledAt'] as Timestamp?)?.toDate(),
      invitedDriverId: d['invitedDriverId'] as String?,
      businessId: d['businessId'] as String?,
      costCenter: d['costCenter'] as String?,
      blockedDriverIds: [for (final s in (d['blockedDriverIds'] as List?) ?? const []) s.toString()],
      visibility: LoadVisibility.all.contains(d['visibility']) ? d['visibility'] as String : LoadVisibility.public,
      allowedDriverIds: [for (final s in (d['allowedDriverIds'] as List?) ?? const []) s.toString()],
      instant: d['instant'] == true,
      postedByRole: d['postedByRole'] as String?,
      fragile: d['fragile'] == true,
      highValue: d['highValue'] == true,
      declaredValuePaise: (d['declaredValuePaise'] as num?)?.toInt(),
      cancelReason: d['cancelReason'] as String?,
      promoCode: (d['promo'] as Map?)?['code'] as String?,
      promoDiscountPaise: ((d['promo'] as Map?)?['discountPaise'] as num?)?.toInt() ?? 0,
      creditsUsedPaise: (d['creditsUsedPaise'] as num?)?.toInt() ?? 0,
    );
  }
}
