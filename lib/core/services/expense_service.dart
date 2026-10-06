import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/vehicle_expense.dart';
import 'backend.dart';

/// Fuel, toll and repair lines per vehicle (V10). Private to the owner.
class ExpenseService {
  ExpenseService._();

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('vehicle_expenses');

  /// All of the signed-in owner's lines, newest first.
  static Stream<List<VehicleExpense>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('ownerId', isEqualTo: uid).snapshots().map((s) => [
          for (final d in s.docs) VehicleExpense.fromDoc(d.id, d.data()),
        ]..sort((a, b) => b.date.compareTo(a.date)));
  }

  static Future<String> add({required String vehicleId, required String kind, required int amountPaise, String note = '', required DateTime date, DateTime? now}) async {
    final today = now ?? DateTime.now();
    if (!ExpenseKind.all.contains(kind)) throw ArgumentError.value(kind, 'kind');
    if (amountPaise < 1 || amountPaise > VehicleExpense.maxPaise) throw ArgumentError.value(amountPaise, 'amountPaise');
    if (note.trim().length > 100) throw ArgumentError.value(note, 'note');
    if (date.isAfter(today.add(const Duration(days: 1))) || date.isBefore(today.subtract(const Duration(days: 1095)))) throw ArgumentError.value(date, 'date');
    final ref = _col.doc();
    await ref.set({
      'ownerId': Backend.requireUid(),
      'vehicleId': vehicleId,
      'kind': kind,
      'amountPaise': amountPaise,
      'note': note.trim(),
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> delete(String id) => _col.doc(id).delete();
}
