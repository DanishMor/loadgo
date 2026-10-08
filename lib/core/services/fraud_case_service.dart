import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/fraud_case.dart';
import '../models/risk.dart';
import 'audit_service.dart';
import 'backend.dart';
import 'risk_service.dart';

/// Admin fraud case management. The rules let only admins touch these
/// documents. TODO(functions): open cases automatically from risk signals.
class FraudCaseService {
  FraudCaseService._();

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('fraud_cases');

  /// Opens a case about [userId]; [reportId] links the report it came from.
  static Future<String> open({required String userId, required String summary, String? reportId}) async {
    final s = summary.trim();
    if (userId.trim().isEmpty || s.length < 3 || s.length > 300) throw ArgumentError('A case needs a user and a short summary');
    final ref = _col.doc();
    await ref.set({
      'userId': userId.trim(),
      'summary': s,
      'status': FraudCase.open,
      'reportIds': [?reportId],
      'createdBy': Backend.requireUid(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Stream<List<FraudCase>> watchAll() => _col.limit(300).snapshots().map((s) {
        final list = [for (final d in s.docs) FraudCase.fromDoc(d.id, d.data())];
        list.sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
        return list;
      });

  static Stream<FraudCase?> watch(String id) =>
      _col.doc(id).snapshots().map((s) => s.exists ? FraudCase.fromDoc(s.id, s.data()!) : null);

  static Stream<List<CaseNote>> watchNotes(String id) => _col.doc(id).collection('notes').snapshots().map((s) {
        final list = [for (final d in s.docs) CaseNote.fromDoc(d.id, d.data())];
        list.sort((a, b) => (a.createdAt ?? DateTime(3000)).compareTo(b.createdAt ?? DateTime(3000)));
        return list;
      });

  static Future<void> addNote(String id, String text) {
    final t = text.trim();
    if (t.isEmpty || t.length > 1000) throw ArgumentError('A note is 1 to 1000 characters');
    return _col.doc(id).collection('notes').add({
      'by': Backend.requireUid(),
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setStatus(String id, String status) {
    if (status != FraudCase.open && status != FraudCase.investigating) throw ArgumentError.value(status, 'status');
    return _col.doc(id).update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Closes the case with a decision. `restricted` and `suspended` also set
  /// the user's risk tier (with the case id as the reason); `dismissed`
  /// closes it with no action.
  static Future<void> close(String id, {required String userId, required String outcome, bool dismiss = false}) async {
    if (!FraudCase.outcomes.contains(outcome)) throw ArgumentError.value(outcome, 'outcome');
    if (outcome == FraudCase.outcomeRestricted) await RiskService.setTier(userId, RiskTier.restricted, reason: 'case $id');
    if (outcome == FraudCase.outcomeSuspended) await RiskService.setTier(userId, RiskTier.suspended, reason: 'case $id');
    final batch = Backend.db.batch();
    batch.update(_col.doc(id), {
      'status': dismiss ? FraudCase.dismissed : FraudCase.resolved,
      'outcome': outcome,
      'resolvedBy': Backend.requireUid(),
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.riskChange, targetId: userId, data: {'case': id, 'outcome': outcome});
    await batch.commit();
  }
}
