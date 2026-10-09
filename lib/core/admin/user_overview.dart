import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// One screen's worth of facts about a person (MASTER-6 Task 11): trips,
/// rating, strikes, tickets, vehicles with expired papers and the audit
/// trail. Numbers only; no phone, address or document number.
class UserOverview {
  final int tripsAsCustomer;
  final int tripsAsDriver;
  final int delivered;
  final int cancelled;
  final int ratingCount;

  /// Average stars times ten (47 = 4.7); null with no rating.
  final int? ratingTenths;
  final int strikes;
  final int violations;
  final int openTickets;
  final int vehicles;
  final int vehiclesWithExpiredPapers;
  final bool verified;
  final bool kycComplete;
  final String riskTier;
  final List<TrailEvent> trail;

  const UserOverview({
    this.tripsAsCustomer = 0,
    this.tripsAsDriver = 0,
    this.delivered = 0,
    this.cancelled = 0,
    this.ratingCount = 0,
    this.ratingTenths,
    this.strikes = 0,
    this.violations = 0,
    this.openTickets = 0,
    this.vehicles = 0,
    this.vehiclesWithExpiredPapers = 0,
    this.verified = false,
    this.kycComplete = false,
    this.riskTier = 'normal',
    this.trail = const [],
  });

  static const trailLimit = 15;

  /// Builds the overview from raw documents. [bookings] holds both the
  /// person's trips as customer and as driver.
  static UserOverview compute({
    required String uid,
    required Map<String, dynamic>? user,
    required Iterable<Map<String, dynamic>> bookings,
    required Iterable<int> stars,
    required int violations,
    required Iterable<Map<String, dynamic>> tickets,
    required Iterable<bool> vehicleHasExpiredPapers,
    required Iterable<Map<String, dynamic>> auditEvents,
  }) {
    var asCustomer = 0, asDriver = 0, delivered = 0, cancelled = 0;
    for (final b in bookings) {
      if (b['customerId'] == uid) asCustomer++;
      if (b['driverId'] == uid || b['fleetOwnerId'] == uid) asDriver++;
      if (b['status'] == 'delivered') delivered++;
      if (b['status'] == 'cancelled') cancelled++;
    }
    final s = stars.where((x) => x >= 1 && x <= 5).toList();
    final trail = <TrailEvent>[
      for (final e in auditEvents)
        TrailEvent(
          type: '${e['type'] ?? ''}',
          action: '${(e['data'] is Map ? (e['data'] as Map)['action'] : null) ?? ''}',
          at: e['createdAt'] is Timestamp ? (e['createdAt'] as Timestamp).toDate() : null,
        ),
    ]..sort((a, b) => (b.at ?? DateTime(1970)).compareTo(a.at ?? DateTime(1970)));
    final u = user ?? const <String, dynamic>{};
    final vehicleList = vehicleHasExpiredPapers.toList();
    return UserOverview(
      tripsAsCustomer: asCustomer,
      tripsAsDriver: asDriver,
      delivered: delivered,
      cancelled: cancelled,
      ratingCount: s.length,
      ratingTenths: s.isEmpty ? null : (s.fold<int>(0, (a, b) => a + b) * 10 / s.length).round(),
      strikes: (u['chatStrikes'] as num?)?.toInt() ?? 0,
      violations: violations,
      openTickets: tickets.where((t) => t['status'] == 'open' || t['status'] == 'in_progress').length,
      vehicles: vehicleList.length,
      vehiclesWithExpiredPapers: vehicleList.where((x) => x).length,
      verified: u['verified'] == true || u['verificationStatus'] == 'approved',
      kycComplete: u['kycComplete'] == true,
      riskTier: '${u['riskTier'] ?? 'normal'}',
      trail: trail.take(trailLimit).toList(),
    );
  }
}

class TrailEvent {
  final String type;
  final String action;
  final DateTime? at;
  const TrailEvent({required this.type, this.action = '', this.at});
}
