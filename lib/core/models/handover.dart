import 'package:cloud_firestore/cloud_firestore.dart';

/// One side of a controlled handover between the leg-1 and leg-2 driver (IE10).
class HandoverSide {
  final String driverId;
  final String bookingId;
  final String sealNumber;
  final String note;
  final DateTime? at;
  const HandoverSide({required this.driverId, required this.bookingId, required this.sealNumber, this.note = '', this.at});

  static HandoverSide? from(Object? m) {
    if (m is! Map) return null;
    return HandoverSide(
      driverId: m['driverId'] as String? ?? '',
      bookingId: m['bookingId'] as String? ?? '',
      sealNumber: m['sealNumber'] as String? ?? '',
      note: m['note'] as String? ?? '',
      at: (m['at'] as Timestamp?)?.toDate(),
    );
  }
}

/// `handovers/{shipmentId}`: leg 1 hands the container over, leg 2 confirms
/// receiving it. Both must confirm; the seal numbers are compared.
class Handover {
  final String shipmentId;
  final HandoverSide? leg1;
  final HandoverSide? leg2;
  final String containerNumber;
  final bool sealMatches;

  const Handover({required this.shipmentId, this.leg1, this.leg2, this.containerNumber = '', this.sealMatches = false});

  bool get complete => leg1 != null && leg2 != null;

  factory Handover.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final l1 = d['leg1'] as Map?;
    final l2 = d['leg2'] as Map?;
    return Handover(
      shipmentId: doc.id,
      leg1: HandoverSide.from(l1),
      leg2: HandoverSide.from(l2),
      containerNumber: l1?['containerNumber'] as String? ?? '',
      sealMatches: l2?['sealMatches'] == true,
    );
  }
}
