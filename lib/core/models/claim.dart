import 'package:cloud_firestore/cloud_firestore.dart';

class ClaimType {
  ClaimType._();
  static const damage = 'damage';
  static const shortage = 'shortage';
  static const delay = 'delay';
  static const payment = 'payment';
  static const behaviour = 'behaviour';
  static const other = 'other';
  static const all = [damage, shortage, delay, payment, behaviour, other];
}

class ClaimStatus {
  ClaimStatus._();
  static const open = 'open';
  static const underReview = 'under_review';
  static const resolved = 'resolved';
}

class ClaimOutcome {
  ClaimOutcome._();
  static const upheld = 'upheld';
  static const partial = 'partial';
  static const declined = 'declined';
  static const all = [upheld, partial, declined];
}

/// `claims/{bookingId}_{openerUid}`. Record only: no money moves in the app.
class Claim {
  static const minDescription = 10;
  static const maxAmountPaise = 10000000;

  final String id;
  final String bookingId;
  final String customerId;
  final String driverId;
  final String openedBy;
  final String type;
  final String description;
  final int? amountPaise;
  final String status;
  final String? outcome;
  final int? awardedPaise;
  final String resolutionNote;
  final DateTime? createdAt;

  const Claim({
    required this.id,
    required this.bookingId,
    required this.customerId,
    required this.driverId,
    required this.openedBy,
    required this.type,
    required this.description,
    this.amountPaise,
    this.status = ClaimStatus.open,
    this.outcome,
    this.awardedPaise,
    this.resolutionNote = '',
    this.createdAt,
  });

  bool get isClosed => status == ClaimStatus.resolved;

  factory Claim.fromDoc(String id, Map<String, dynamic> d) => Claim(
        id: id,
        bookingId: d['bookingId'] as String? ?? '',
        customerId: d['customerId'] as String? ?? '',
        driverId: d['driverId'] as String? ?? '',
        openedBy: d['openedBy'] as String? ?? '',
        type: d['type'] as String? ?? ClaimType.other,
        description: d['description'] as String? ?? '',
        amountPaise: (d['amountPaise'] as num?)?.toInt(),
        status: d['status'] as String? ?? ClaimStatus.open,
        outcome: d['outcome'] as String?,
        awardedPaise: (d['awardedPaise'] as num?)?.toInt(),
        resolutionNote: d['resolutionNote'] as String? ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// `claims/{id}/events/{auto}`: the append-only timeline.
class ClaimEvent {
  final String id;
  final String by;
  final String role;
  final String kind;
  final String text;
  final DateTime? createdAt;

  const ClaimEvent({required this.id, required this.by, required this.role, required this.kind, required this.text, this.createdAt});

  factory ClaimEvent.fromDoc(String id, Map<String, dynamic> d) => ClaimEvent(
        id: id,
        by: d['by'] as String? ?? '',
        role: d['role'] as String? ?? '',
        kind: d['kind'] as String? ?? 'message',
        text: d['text'] as String? ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}
