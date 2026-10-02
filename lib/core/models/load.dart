import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';

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
  final String? driverId;
  final String? bookingId;
  final Timestamp? createdAt;

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
    this.driverId,
    this.bookingId,
    this.createdAt,
  });

  bool get isOpen => status == LoadStatus.open;

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
      driverId: d['driverId'] as String?,
      bookingId: d['bookingId'] as String?,
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}
