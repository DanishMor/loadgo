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
  final DateTime? nextTyreCheckDate;

  /// Driver a transporter gave this vehicle to (null = the owner drives it).
  final String? assignedDriverId;

  /// Transporter this vehicle is attached to (its owner is a member of that
  /// fleet and agreed to it); null when not attached.
  final String? attachedTo;

  /// Optional profile: cargo space in metres, fuel and body type.
  final VehicleProfile profile;

  /// An admin lets the vehicle work with expired papers until this time.
  final DateTime? docOverrideUntil;

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
    this.nextTyreCheckDate,
    this.assignedDriverId,
    this.attachedTo,
    this.profile = const VehicleProfile(),
    this.docOverrideUntil,
  });

  bool get isActive => status == VehicleStatus.active;

  /// Active and free to take a new booking.
  bool get canTakeBooking => isActive && availability == VehicleAvailability.available;

  /// Kinds whose expiry is on or before `now + days` (already expired included).
  List<String> docsExpiringWithin(DateTime now, {int days = 30}) => [
        for (final k in VehicleDocKind.all)
          if (docs[k]?.expiry case final e? when !e.isAfter(now.add(Duration(days: days)))) k,
      ];

  bool overrideActive(DateTime now) => docOverrideUntil != null && docOverrideUntil!.isAfter(now);

  /// Expired insurance / permit / fitness papers.
  List<String> blockingExpired(DateTime now) => [for (final k in expiredDocs(now)) if (VehicleDocKind.blocking.contains(k)) k];

  /// True when expired papers keep this vehicle off bookings (no admin override).
  bool papersBlocked(DateTime now) => blockingExpired(now).isNotEmpty && !overrideActive(now);

  List<String> expiredDocs(DateTime now) => [
        for (final k in VehicleDocKind.all)
          if (docs[k]?.isExpired(now) == true) k,
      ];

  /// Service is due within a week (or overdue).
  bool serviceDue(DateTime now) =>
      nextServiceDate != null && !nextServiceDate!.isAfter(now.add(const Duration(days: 7)));

  /// Tyre check is due within a week (or overdue).
  bool tyreDue(DateTime now) =>
      nextTyreCheckDate != null && !nextTyreCheckDate!.isAfter(now.add(const Duration(days: 7)));

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
      nextTyreCheckDate: (d['nextTyreCheckDate'] as Timestamp?)?.toDate(),
      assignedDriverId: d['assignedDriverId'] as String?,
      attachedTo: d['attachedTo'] as String?,
      profile: VehicleProfile.fromMap(d),
      docOverrideUntil: (d['docOverrideUntil'] as Timestamp?)?.toDate(),
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

/// Cargo space (metres), fuel and body type; all optional.
class VehicleProfile {
  final double? lengthM;
  final double? widthM;
  final double? heightM;
  final String? fuel;
  final String? bodyType;

  const VehicleProfile({this.lengthM, this.widthM, this.heightM, this.fuel, this.bodyType});

  bool get isEmpty => lengthM == null && widthM == null && heightM == null && fuel == null && bodyType == null;

  /// Largest side allowed for any dimension (metres).
  static const maxDimensionM = 30.0;

  static bool validDimension(double? v) => v == null || (v > 0 && v <= maxDimensionM);

  bool get valid => validDimension(lengthM) && validDimension(widthM) && validDimension(heightM) &&
      (fuel == null || FuelType.all.contains(fuel)) && (bodyType == null || BodyType.all.contains(bodyType));

  factory VehicleProfile.fromMap(Map<String, dynamic> d) => VehicleProfile(
        lengthM: (d['lengthM'] as num?)?.toDouble(),
        widthM: (d['widthM'] as num?)?.toDouble(),
        heightM: (d['heightM'] as num?)?.toDouble(),
        fuel: d['fuel'] as String?,
        bodyType: d['bodyType'] as String?,
      );

  /// Fields to write; empty ones are deleted on update (see [toUpdate]).
  Map<String, Object> toMap() => {
        'lengthM': ?lengthM,
        'widthM': ?widthM,
        'heightM': ?heightM,
        'fuel': ?fuel,
        'bodyType': ?bodyType,
      };

  Map<String, Object> toUpdate() => {
        'lengthM': lengthM ?? FieldValue.delete(),
        'widthM': widthM ?? FieldValue.delete(),
        'heightM': heightM ?? FieldValue.delete(),
        'fuel': fuel ?? FieldValue.delete(),
        'bodyType': bodyType ?? FieldValue.delete(),
      };

  /// "6.1 x 2.4 x 2.4 m" or null when no dimensions are set.
  String? get dimensionsText {
    if (lengthM == null && widthM == null && heightM == null) return null;
    String f(double? v) => v == null ? '-' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());
    return '${f(lengthM)} × ${f(widthM)} × ${f(heightM)} m';
  }
}
