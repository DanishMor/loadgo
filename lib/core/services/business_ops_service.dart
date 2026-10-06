import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../enterprise/business_roles.dart';
import '../models/booking.dart';
import '../models/business_ops.dart';
import '../models/load.dart';
import 'backend.dart';
import 'business_service.dart';

class BusinessOpsException implements Exception {
  final String reason;
  const BusinessOpsException(this.reason);
  @override
  String toString() => 'BusinessOpsException($reason)';
}

/// Approvals, contract vehicles, the approved driver pool and the expense
/// dashboard of a company account (BIZ6, BIZ8, BIZ9, BIZ10). Records only.
class BusinessOpsService {
  BusinessOpsService._();

  static FirebaseFirestore get _db => Backend.db;
  static CollectionReference<Map<String, dynamic>> _col(String n) => _db.collection(n);

  // ---- approval (BIZ6) ----

  static Future<int> approvalLimit(String ownerId) async {
    final d = (await _col('business_settings').doc(ownerId).get()).data();
    return (d?['approvalLimitPaise'] as num?)?.round() ?? 0;
  }

  /// Owner: loads above [paise] posted by other members wait for approval (0 = off).
  static Future<void> setApprovalLimit(int paise) {
    if (paise < 0 || paise > 100000000000) throw ArgumentError.value(paise, 'paise');
    final uid = Backend.requireUid();
    return _col('business_settings').doc(uid).set({'ownerId': uid, 'approvalLimitPaise': paise, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Would a load of [amountPaise] posted now for [ownerId] wait for approval?
  /// Not for the owner, not for managers, not when no limit is set.
  static Future<bool> approvalNeeded(String ownerId, int amountPaise) async {
    final uid = Backend.requireUid();
    if (ownerId == uid) return false;
    final limit = await approvalLimit(ownerId);
    if (limit <= 0 || amountPaise <= limit) return false;
    final m = (await _col('business_members').doc('${ownerId}_$uid').get()).data();
    return m?['role'] != BizRole.manager;
  }

  static Stream<List<Load>> watchAwaitingApproval(String ownerId) => _col('loads')
      .where('businessId', isEqualTo: ownerId)
      .where('status', isEqualTo: LoadStatus.awaitingApproval)
      .snapshots()
      .map((s) => s.docs.map(Load.fromDoc).toList());

  static Future<void> decide(Load l, {required bool approve}) {
    final uid = Backend.requireUid();
    return _col('loads').doc(l.id).update({
      'status': approve ? LoadStatus.open : LoadStatus.closed,
      if (!approve) 'cancelled': true,
      'approval': {'by': uid, 'at': FieldValue.serverTimestamp(), 'decision': approve ? 'approved' : 'rejected'},
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- contract vehicles (BIZ8) ----

  static Stream<List<ContractVehicle>> watchContracts(String ownerId) => _col('business_contracts')
      .where('ownerId', isEqualTo: ownerId)
      .snapshots()
      .map((s) => [for (final d in s.docs) ContractVehicle.fromDoc(d.id, d.data())]..sort((a, b) => a.vehicleNumber.compareTo(b.vehicleNumber)));

  static Future<void> addContract(String ownerId, {required String vehicleNumber, required String vehicleType, required String vendorName, int? ratePerTripPaise, DateTime? validUntil, String note = ''}) {
    final number = vehicleNumber.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (number.length < 4 || number.length > 15 || vendorName.trim().length < 2 || vendorName.trim().length > 80 || note.trim().length > 200) {
      throw const BusinessOpsException('invalid');
    }
    if (ratePerTripPaise != null && (ratePerTripPaise < 0 || ratePerTripPaise > 1000000000)) throw const BusinessOpsException('invalid');
    return _col('business_contracts').add({
      'ownerId': ownerId,
      'vehicleNumber': number,
      'vehicleType': vehicleType,
      'vendorName': vendorName.trim(),
      'ratePerTripPaise': ?ratePerTripPaise,
      'validUntil': ?(validUntil == null ? null : Timestamp.fromDate(validUntil)),
      if (note.trim().isNotEmpty) 'note': note.trim(),
      'addedBy': Backend.requireUid(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteContract(String id) => _col('business_contracts').doc(id).delete();

  // ---- approved driver pool (BIZ9) ----

  static Stream<List<PoolDriver>> watchPool(String ownerId) => _col('business_pool')
      .where('ownerId', isEqualTo: ownerId)
      .snapshots()
      .map((s) => [for (final d in s.docs) PoolDriver.fromDoc(d.data())]..sort((a, b) => a.name.compareTo(b.name)));

  static Future<List<String>> poolIds(String ownerId) async =>
      [for (final d in (await _col('business_pool').where('ownerId', isEqualTo: ownerId).get()).docs) d.data()['driverId'] as String];

  static Future<void> addToPool(String ownerId, {required String driverId, required String name, String vehicleNumber = ''}) {
    if (driverId.isEmpty) throw const BusinessOpsException('invalid');
    return _col('business_pool').doc('${ownerId}_$driverId').set({
      'ownerId': ownerId,
      'driverId': driverId,
      'driverName': name.trim(),
      if (vehicleNumber.isNotEmpty) 'vehicleNumber': vehicleNumber,
      'addedBy': Backend.requireUid(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> removeFromPool(String ownerId, String driverId) => _col('business_pool').doc('${ownerId}_$driverId').delete();

  // ---- expenses (BIZ10) ----

  static Stream<List<BizExpense>> watchExpenses(String ownerId) => _col('business_expenses')
      .where('ownerId', isEqualTo: ownerId)
      .snapshots()
      .map((s) => [for (final d in s.docs) BizExpense.fromDoc(d.id, d.data())]..sort((a, b) => b.date.compareTo(a.date)));

  static Future<void> addExpense(String ownerId, {required String kind, required int amountPaise, required DateTime date, String costCenter = '', String note = '', DateTime? now}) {
    if (!BizExpenseKind.all.contains(kind) || amountPaise < 1 || amountPaise > 10000000000 || costCenter.trim().length > 30 || note.trim().length > 100) {
      throw const BusinessOpsException('invalid');
    }
    if (date.isAfter((now ?? DateTime.now()).add(const Duration(days: 1)))) throw const BusinessOpsException('future');
    return _col('business_expenses').add({
      'ownerId': ownerId,
      'kind': kind,
      'amountPaise': amountPaise,
      'date': Timestamp.fromDate(date),
      if (costCenter.trim().isNotEmpty) 'costCenter': costCenter.trim(),
      if (note.trim().isNotEmpty) 'note': note.trim(),
      'addedBy': Backend.requireUid(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteExpense(String id) => _col('business_expenses').doc(id).delete();

  /// Delivered bookings of the company, for the dashboard.
  static Stream<List<Booking>> watchCompanyBookings(String ownerId) =>
      _col('bookings').where('businessId', isEqualTo: ownerId).snapshots().map((s) => s.docs.map(Booking.fromDoc).toList());

  /// Convenience for the hub: the company's context of the signed-in user.
  static Future<BizContext?> context() => BusinessService.myContext();
}
