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
  final String? rcImageUrl;
  final Timestamp? createdAt;

  /// [VehicleAvailability] value; old documents default to available.
  final String availability;

  /// Insurance/PUC/fitness/permit details keyed by [VehicleDocKind].
  final Map<String, VehicleDocInfo> docs;
  final DateTime? nextServiceDate;

  const Vehicle({
    required this.id,
    required this.ownerId,
    required this.number,
    required this.type,
    required this.capacity,
    required this.rcNumber,
    required this.status,
    this.rcImageUrl,
    this.createdAt,
    this.availability = VehicleAvailability.available,
    this.docs = const {},
    this.nextServiceDate,
  });

  bool get isActive => status == VehicleStatus.active;

  /// Active and free to take a new booking.
  bool get canTakeBooking => isActive && availability == VehicleAvailability.available;

  /// Kinds whose expiry is on or before `now + days` (already expired included).
  List<String> docsExpiringWithin(DateTime now, {int days = 30}) => [
        for (final k in VehicleDocKind.all)
          if (docs[k]?.expiry case final e? when !e.isAfter(now.add(Duration(days: days)))) k,
      ];

  List<String> expiredDocs(DateTime now) => [
        for (final k in VehicleDocKind.all)
          if (docs[k]?.isExpired(now) == true) k,
      ];

  /// Service is due within a week (or overdue).
  bool serviceDue(DateTime now) =>
      nextServiceDate != null && !nextServiceDate!.isAfter(now.add(const Duration(days: 7)));

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
      rcImageUrl: d['rcImageUrl'] as String?,
      createdAt: d['createdAt'] as Timestamp?,
      availability: d['availability'] as String? ?? VehicleAvailability.available,
      docs: {
        for (final e in ((d['docs'] as Map?) ?? const {}).entries)
          if (e.value is Map) e.key as String: VehicleDocInfo.fromMap(Map<String, dynamic>.from(e.value as Map)),
      },
      nextServiceDate: (d['nextServiceDate'] as Timestamp?)?.toDate(),
    );
  }
}

/// One compliance paper. Never verified by LoadGo yet, so always shown as
/// "Unverified". LATER(paid): RC/insurance verification via a KYC API.
class VehicleDocInfo {
  final String number;
  final DateTime? expiry;

  const VehicleDocInfo({this.number = '', this.expiry});

  bool get isEmpty => number.isEmpty && expiry == null;

  bool isExpired(DateTime now) => expiry != null && expiry!.isBefore(DateTime(now.year, now.month, now.day));

  factory VehicleDocInfo.fromMap(Map<String, dynamic> m) => VehicleDocInfo(
        number: m['number'] as String? ?? '',
        expiry: (m['expiry'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'number': number,
        if (expiry != null) 'expiry': Timestamp.fromDate(expiry!),
      };
}
