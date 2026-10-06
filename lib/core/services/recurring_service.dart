import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/recurring.dart';
import '../models/repeat.dart';
import 'backend.dart';

class RecurringLimitException implements Exception {
  @override
  String toString() => 'RecurringLimitException';
}

/// Repeating shipments (P3), private to the customer. Nothing is posted
/// unattended; see [RecurringLoad].
class RecurringService {
  RecurringService._();

  static CollectionReference<Map<String, dynamic>> _col([String? uid]) =>
      Backend.db.collection('users').doc(uid ?? Backend.requireUid()).collection('recurring_loads');

  static Stream<List<RecurringLoad>> watch() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col(uid).snapshots().map((s) => [
          for (final d in s.docs) RecurringLoad.fromDoc(d.id, d.data()),
        ]..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt)));
  }

  /// Saves a repeating shipment. [first] is the date of the occurrence that
  /// was just posted, so the next one is due a week / month later.
  static Future<String> create(LoadTemplate t, String frequency, {required DateTime first}) async {
    if (!Frequency.all.contains(frequency)) throw ArgumentError.value(frequency, 'frequency');
    final col = _col();
    if ((await col.get()).size >= RecurringLoad.maxPerUser) throw RecurringLimitException();
    final ref = col.doc();
    final r = RecurringLoad(id: ref.id, template: t, frequency: frequency, nextDueAt: Frequency.next(first, frequency));
    await ref.set({...r.toMap(), 'name': t.name.trim(), 'createdAt': FieldValue.serverTimestamp()});
    return ref.id;
  }

  /// After the due occurrence was posted (or skipped): the next date after
  /// [from], moved past today if the customer was away for a while.
  static Future<void> advance(RecurringLoad r, {DateTime? from, DateTime? now}) async {
    final today = now ?? DateTime.now();
    var next = Frequency.next(from ?? r.nextDueAt, r.frequency);
    while (!next.isAfter(today)) {
      next = Frequency.next(next, r.frequency);
    }
    await _col().doc(r.id).update({'nextDueAt': Timestamp.fromDate(next)});
  }

  static Future<void> setActive(String id, bool active) => _col().doc(id).update({'active': active});

  static Future<void> delete(String id) => _col().doc(id).delete();
}
