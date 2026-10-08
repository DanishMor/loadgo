import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/backend.dart';
import 'call_models.dart';

/// The Firestore side of an in-app call (free WebRTC signalling): the offer,
/// the answer and the network candidates. The audio never goes through
/// Firestore. Documents hold no phone number.
class CallSignaling {
  CallSignaling._();

  static CollectionReference<Map<String, dynamic>> get _calls => Backend.db.collection('calls');

  static String _clip(String s, int max) => s.length > max ? s.substring(0, max) : s;

  /// Creates a ringing call to [calleeId] and returns its id.
  static Future<String> create({
    required String bookingId,
    required String calleeId,
    required String callerName,
    required String vehicleNumber,
    required String offerSdp,
  }) async {
    final uid = Backend.requireUid();
    final ref = _calls.doc();
    await ref.set({
      'bookingId': bookingId,
      'callerId': uid,
      'calleeId': calleeId,
      'callerName': _clip(callerName, 60),
      'vehicleNumber': _clip(vehicleNumber, 12),
      'status': CallStatus.ringing,
      'offer': {'type': 'offer', 'sdp': offerSdp},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Calls ringing for the signed-in person (the app is open, so it rings).
  static Stream<List<CallDoc>> watchIncoming() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _calls
        .where('calleeId', isEqualTo: uid)
        .where('status', isEqualTo: CallStatus.ringing)
        .snapshots()
        .map((s) => [for (final d in s.docs) CallDoc.fromMap(d.id, d.data())]);
  }

  static Stream<CallDoc?> watch(String callId) =>
      _calls.doc(callId).snapshots().map((s) => s.exists ? CallDoc.fromMap(s.id, s.data()!) : null);

  static Future<void> accept(String callId, String answerSdp) => _calls.doc(callId).update({
        'status': CallStatus.accepted,
        'answer': {'type': 'answer', 'sdp': answerSdp},
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> _setStatus(String callId, String status) =>
      _calls.doc(callId).update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});

  static Future<void> decline(String callId) => _setStatus(callId, CallStatus.declined);
  static Future<void> cancel(String callId) => _setStatus(callId, CallStatus.cancelled);
  static Future<void> end(String callId) => _setStatus(callId, CallStatus.ended);

  static Future<void> addCandidate(String callId, CallCandidate c) => _calls.doc(callId).collection('candidates').add({
        'from': Backend.requireUid(),
        'candidate': _clip(c.candidate, 1000),
        'sdpMid': c.sdpMid ?? '',
        'sdpMLineIndex': c.sdpMLineIndex ?? 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

  /// Candidates the other side adds (new ones as they arrive).
  static Stream<CallCandidate> watchRemoteCandidates(String callId) {
    final me = Backend.requireUid();
    return _calls.doc(callId).collection('candidates').snapshots().expand((s) => [
          for (final ch in s.docChanges)
            if (ch.type == DocumentChangeType.added && ch.doc.data()?['from'] != me)
              CallCandidate(
                from: ch.doc.data()!['from'] as String? ?? '',
                candidate: ch.doc.data()!['candidate'] as String? ?? '',
                sdpMid: ch.doc.data()!['sdpMid'] as String?,
                sdpMLineIndex: (ch.doc.data()!['sdpMLineIndex'] as num?)?.toInt(),
              ),
        ]);
  }
}
