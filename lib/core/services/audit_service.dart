import 'package:cloud_firestore/cloud_firestore.dart';

import 'backend.dart';

/// Append-only `audit_events`, written alongside the action they describe.
/// TODO(functions): write these from triggers so clients cannot skip them.
class AuditType {
  AuditType._();
  static const verification = 'verification';
  static const accept = 'accept';
  static const statusChange = 'status_change';
  static const cancel = 'cancel';
  static const riskChange = 'risk_change';
  static const reassign = 'reassign';
  static const configChange = 'config_change';
  static const userAction = 'user_action';

  /// A transporter assigned or reassigned the vehicle and driver of a booking.
  static const assign = 'assign';

  /// A party wrote evidence on a booking (GPS, odometer, signature, cargo document, accident).
  static const evidence = 'evidence';

  /// A party opened the cargo documents of a booking.
  static const docView = 'doc_view';
  static const all = [verification, accept, statusChange, cancel, riskChange, reassign, configChange, userAction, evidence, docView, assign];
}

class AuditService {
  AuditService._();

  static Map<String, Object?> _event(String type, {String? targetId, String? bookingId, String? loadId, Map<String, Object?>? data}) => {
        'type': type,
        'actorId': Backend.requireUid(),
        'targetId': ?targetId,
        'bookingId': ?bookingId,
        'loadId': ?loadId,
        'data': data ?? const {},
        'createdAt': FieldValue.serverTimestamp(),
      };

  static DocumentReference<Map<String, dynamic>> _newRef() => Backend.db.collection('audit_events').doc();

  static void inTransaction(Transaction tx, String type,
          {String? targetId, String? bookingId, String? loadId, Map<String, Object?>? data}) =>
      tx.set(_newRef(), _event(type, targetId: targetId, bookingId: bookingId, loadId: loadId, data: data));

  static void inBatch(WriteBatch batch, String type,
          {String? targetId, String? bookingId, String? loadId, Map<String, Object?>? data}) =>
      batch.set(_newRef(), _event(type, targetId: targetId, bookingId: bookingId, loadId: loadId, data: data));

  /// Writes one event on its own (for actions that are not part of a batch).
  static Future<void> record(String type, {String? targetId, String? bookingId, String? loadId, Map<String, Object?>? data}) =>
      _newRef().set(_event(type, targetId: targetId, bookingId: bookingId, loadId: loadId, data: data));
}
