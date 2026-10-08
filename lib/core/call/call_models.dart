import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/booking.dart';

/// `calls/{id}.status`. Keep in sync with firestore.rules.
class CallStatus {
  CallStatus._();
  static const ringing = 'ringing';
  static const accepted = 'accepted';
  static const declined = 'declined';
  static const cancelled = 'cancelled';
  static const ended = 'ended';

  static const finished = [declined, cancelled, ended];
}

/// A call is only possible while a booking is confirmed and not finished
/// (same statuses as the rules, `callBookingOk`).
bool bookingAllowsCall(Booking b) =>
    b.status != BookingStatus.delivered && b.status != BookingStatus.cancelled && BookingStatus.flow.contains(b.status);

/// Who the signed-in person rings from a booking: the customer rings whoever
/// runs the trip (the assigned driver, else the booking holder); a driver or
/// the transporter rings the customer; the transporter rings their assigned
/// driver when [preferDriver] is set. Null when there is nobody to ring.
String? callTarget(Booking b, String me, {bool preferDriver = false}) {
  if (me == b.customerId) return b.runningDriverId;
  if (me == b.driverId && preferDriver && b.assignedDriverId != null && b.assignedDriverId != me) return b.assignedDriverId;
  if (me == b.driverId || me == b.assignedDriverId) return b.customerId;
  return null;
}

/// How long a call rings before it counts as missed.
const callRingTimeout = Duration(seconds: 45);

/// A call document, as the callee or the caller sees it. It holds no phone number.
class CallDoc {
  final String id;
  final String bookingId;
  final String callerId;
  final String calleeId;
  final String callerName;
  final String vehicleNumber;
  final String status;
  final String? offerSdp;
  final String? answerSdp;
  final DateTime? createdAt;

  const CallDoc({
    required this.id,
    required this.bookingId,
    required this.callerId,
    required this.calleeId,
    this.callerName = '',
    this.vehicleNumber = '',
    required this.status,
    this.offerSdp,
    this.answerSdp,
    this.createdAt,
  });

  bool get isLive => status == CallStatus.ringing || status == CallStatus.accepted;

  /// Rings only while it is fresh: a call nobody picked up for a minute is
  /// not shown (the phone clock may be a little off, so a small lead is fine).
  bool isFresh(DateTime now) {
    final at = createdAt;
    if (at == null) return true;
    final age = now.difference(at);
    return age < callRingTimeout + const Duration(seconds: 15) && age > const Duration(seconds: -90);
  }

  factory CallDoc.fromMap(String id, Map<String, dynamic> d) => CallDoc(
        id: id,
        bookingId: d['bookingId'] as String? ?? '',
        callerId: d['callerId'] as String? ?? '',
        calleeId: d['calleeId'] as String? ?? '',
        callerName: d['callerName'] as String? ?? '',
        vehicleNumber: d['vehicleNumber'] as String? ?? '',
        status: d['status'] as String? ?? CallStatus.ended,
        offerSdp: (d['offer'] as Map?)?['sdp'] as String?,
        answerSdp: (d['answer'] as Map?)?['sdp'] as String?,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// One network candidate swapped through `calls/{id}/candidates`.
class CallCandidate {
  final String from;
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  const CallCandidate({required this.from, required this.candidate, this.sdpMid, this.sdpMLineIndex});
}
