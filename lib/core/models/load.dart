import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../pricing/fare_calculator.dart';

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
  });

  bool get isOpen => status == LoadStatus.open;

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
    );
  }
}
