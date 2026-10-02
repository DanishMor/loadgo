import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';

class Vehicle {
  final String id;
  final String ownerId;
  final String number;
  final String type;
  final num capacity;
  final String rcNumber;
  final String status;
  final Timestamp? createdAt;

  const Vehicle({
    required this.id,
    required this.ownerId,
    required this.number,
    required this.type,
    required this.capacity,
    required this.rcNumber,
    required this.status,
    this.createdAt,
  });

  bool get isActive => status == VehicleStatus.active;

  factory Vehicle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Vehicle(
      id: doc.id,
      ownerId: d['ownerId'] as String? ?? '',
      number: d['number'] as String? ?? '',
      type: d['type'] as String? ?? '',
      capacity: d['capacity'] as num? ?? 0,
      rcNumber: d['rcNumber'] as String? ?? '',
      status: d['status'] as String? ?? VehicleStatus.inactive,
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}
