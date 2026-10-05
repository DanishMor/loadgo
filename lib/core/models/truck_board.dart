import 'package:cloud_firestore/cloud_firestore.dart';

import 'load.dart';
import 'load_filter.dart' show parseIsoDate;

/// `truck_posts/{id}`: a driver's empty truck, "free from A to B on a date".
/// Customers browse the board and send a request.
class TruckPost {
  final String id;
  final String driverId;
  final String driverName;
  final String vehicleId;
  final String vehicleNumber;
  final String vehicleType;
  final num capacity;
  final String fromCity;
  final String toCity;
  final DateTime availableDate;
  final String note;
  final String status;
  final DateTime? createdAt;

  const TruckPost({
    required this.id,
    required this.driverId,
    this.driverName = '',
    required this.vehicleId,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.capacity,
    required this.fromCity,
    required this.toCity,
    required this.availableDate,
    this.note = '',
    required this.status,
    this.createdAt,
  });

  static const open = 'open';
  static const closed = 'closed';

  /// Furthest ahead a post can be dated.
  static const maxDaysAhead = 30;

  bool isOpenOn(DateTime now) => status == open && !DateTime(availableDate.year, availableDate.month, availableDate.day).isBefore(DateTime(now.year, now.month, now.day));

  factory TruckPost.fromDoc(String id, Map<String, dynamic> d) => TruckPost(
        id: id,
        driverId: d['driverId'] as String? ?? '',
        driverName: d['driverName'] as String? ?? '',
        vehicleId: d['vehicleId'] as String? ?? '',
        vehicleNumber: d['vehicleNumber'] as String? ?? '',
        vehicleType: d['vehicleType'] as String? ?? '',
        capacity: d['capacity'] as num? ?? 0,
        fromCity: d['fromCity'] as String? ?? '',
        toCity: d['toCity'] as String? ?? '',
        availableDate: (d['availableDate'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
        note: d['note'] as String? ?? '',
        status: d['status'] as String? ?? open,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// Board filter: text on from/to (matched as in the city table by simple
/// containment), vehicle type, a date range and a minimum capacity in tons.
class TruckFilter {
  final String from;
  final String to;
  final String? vehicleType;
  final DateTime? onOrAfter;
  final DateTime? onOrBefore;
  final num? minCapacity;

  const TruckFilter({this.from = '', this.to = '', this.vehicleType, this.onOrAfter, this.onOrBefore, this.minCapacity});

  static const none = TruckFilter();

  bool get isEmpty =>
      from.trim().isEmpty && to.trim().isEmpty && vehicleType == null && onOrAfter == null && onOrBefore == null && minCapacity == null;

  bool matches(TruckPost p) {
    bool has(String hay, String needle) => needle.trim().isEmpty || hay.toLowerCase().contains(needle.trim().toLowerCase());
    if (!has(p.fromCity, from) || !has(p.toCity, to)) return false;
    if (vehicleType != null && p.vehicleType != vehicleType) return false;
    if (minCapacity != null && p.capacity < minCapacity!) return false;
    final day = DateTime(p.availableDate.year, p.availableDate.month, p.availableDate.day);
    if (onOrAfter != null && day.isBefore(DateTime(onOrAfter!.year, onOrAfter!.month, onOrAfter!.day))) return false;
    if (onOrBefore != null && day.isAfter(DateTime(onOrBefore!.year, onOrBefore!.month, onOrBefore!.day))) return false;
    return true;
  }

  static String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Stored form of a saved search (only the fields in use).
  Map<String, Object?> toMap() => {
        if (from.trim().isNotEmpty) 'from': from.trim(),
        if (to.trim().isNotEmpty) 'to': to.trim(),
        'vehicleType': ?vehicleType,
        'minCapacity': ?minCapacity,
        if (onOrAfter != null) 'onOrAfter': _iso(onOrAfter!),
        if (onOrBefore != null) 'onOrBefore': _iso(onOrBefore!),
      };

  factory TruckFilter.fromMap(Map<String, dynamic> m) => TruckFilter(
        from: m['from'] as String? ?? '',
        to: m['to'] as String? ?? '',
        vehicleType: m['vehicleType'] as String?,
        minCapacity: m['minCapacity'] as num?,
        onOrAfter: parseIsoDate(m['onOrAfter']),
        onOrBefore: parseIsoDate(m['onOrBefore']),
      );
}

/// `truck_requests/{postId}_{customerId}`: a customer asks for a posted truck.
/// The driver accepts or declines; an accepted request lets the customer post
/// the load reserved for that driver.
class TruckRequest {
  final String id;
  final String postId;
  final String driverId;
  final String customerId;
  final String customerName;
  final String pickup;
  final String drop;
  final num weight;
  final String cargoType;
  final String note;
  final String vehicleType;
  final String status;
  final DateTime? createdAt;

  const TruckRequest({
    required this.id,
    required this.postId,
    required this.driverId,
    required this.customerId,
    this.customerName = '',
    required this.pickup,
    required this.drop,
    required this.weight,
    this.cargoType = '',
    this.note = '',
    this.vehicleType = '',
    required this.status,
    this.createdAt,
  });

  static const pending = 'pending';
  static const accepted = 'accepted';
  static const declined = 'declined';
  static const withdrawn = 'withdrawn';

  static String idFor(String postId, String customerId) => '${postId}_$customerId';

  factory TruckRequest.fromDoc(String id, Map<String, dynamic> d) => TruckRequest(
        id: id,
        postId: d['postId'] as String? ?? '',
        driverId: d['driverId'] as String? ?? '',
        customerId: d['customerId'] as String? ?? '',
        customerName: d['customerName'] as String? ?? '',
        pickup: d['pickup'] as String? ?? '',
        drop: d['drop'] as String? ?? '',
        weight: d['weight'] as num? ?? 0,
        cargoType: d['cargoType'] as String? ?? '',
        note: d['note'] as String? ?? '',
        vehicleType: d['vehicleType'] as String? ?? '',
        status: d['status'] as String? ?? pending,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );

  /// A load pre-filled from this request, for the customer's Post Load form.
  Load toLoadDraft() => Load(
        id: '',
        shipperId: customerId,
        pickup: pickup,
        drop: drop,
        cargoType: cargoType,
        weight: weight,
        vehicleType: vehicleType,
        budget: null,
        pickupDate: null,
        notes: note,
        status: 'open',
        invitedDriverId: driverId,
      );
}
