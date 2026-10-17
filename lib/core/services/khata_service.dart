import 'package:cloud_firestore/cloud_firestore.dart';

import '../khata/khata_models.dart';
import 'backend.dart';

/// Party khata of the signed-in person (G23): `users/{uid}/khata/{partyId}` with a running balance, and
/// `.../entries/{id}` for each line. Private to the owner (the rules say so). The balance is changed together with the
/// entry in one batch, so the two cannot drift apart.
class KhataService {
  KhataService._();

  static CollectionReference<Map<String, dynamic>> get _parties => Backend.db.collection('users').doc(Backend.requireUid()).collection('khata');

  static Stream<List<KhataParty>> watchParties() {
    if (Backend.uid == null) return Stream.value(const []);
    // At most 100 parties exist (the app refuses more), so the list is bounded.
    return _parties.limit(KhataParty.maxParties).snapshots().map((s) => [for (final d in s.docs) KhataParty.fromDoc(d.id, d.data())]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
  }

  /// The newest 500 lines of one party (the balance is kept on the party, so older lines do not change it).
  static const maxShownLines = 500;

  static Stream<List<KhataEntry>> watchEntries(String partyId) => _parties
      .doc(partyId)
      .collection('entries')
      .orderBy('createdAt', descending: true)
      .limit(maxShownLines)
      .snapshots()
      .map((s) => [for (final d in s.docs) KhataEntry.fromDoc(d.id, d.data())]..sort((a, b) => b.date.compareTo(a.date)));

  static Future<String> addParty(String name, {String note = '', int currentCount = 0}) async {
    final n = name.trim();
    if (n.isEmpty || n.length > KhataParty.maxName) throw ArgumentError.value(name, 'name');
    if (note.trim().length > KhataParty.maxNote) throw ArgumentError.value(note, 'note');
    if (currentCount >= KhataParty.maxParties) throw StateError('too many parties');
    final ref = _parties.doc();
    await ref.set({'name': n, 'note': note.trim(), 'balancePaise': 0, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    return ref.id;
  }

  static Future<void> addEntry(String partyId, {required String kind, required int amountPaise, String note = '', required DateTime date, DateTime? now}) async {
    if (!KhataEntryKind.all.contains(kind)) throw ArgumentError.value(kind, 'kind');
    if (amountPaise < 1 || amountPaise > KhataEntry.maxPaise) throw ArgumentError.value(amountPaise, 'amountPaise');
    if (note.trim().length > KhataEntry.maxNote) throw ArgumentError.value(note, 'note');
    final today = now ?? DateTime.now();
    if (date.isAfter(today.add(const Duration(days: 1))) || date.isBefore(today.subtract(const Duration(days: 1095)))) throw ArgumentError.value(date, 'date');
    final partyRef = _parties.doc(partyId);
    final entryRef = partyRef.collection('entries').doc();
    final delta = kind == KhataEntryKind.owed ? amountPaise : -amountPaise;
    final batch = Backend.db.batch();
    batch.set(entryRef, {
      'kind': kind,
      'amountPaise': amountPaise,
      'note': note.trim(),
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(partyRef, {'balancePaise': FieldValue.increment(delta), 'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  /// A wrong line is removed and the balance is corrected in the same batch.
  static Future<void> deleteEntry(String partyId, KhataEntry e) async {
    final partyRef = _parties.doc(partyId);
    final batch = Backend.db.batch();
    batch.delete(partyRef.collection('entries').doc(e.id));
    batch.update(partyRef, {'balancePaise': FieldValue.increment(-e.signed), 'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  /// Deletes a party and all its lines.
  static Future<void> deleteParty(String partyId) async {
    final partyRef = _parties.doc(partyId);
    final entries = await partyRef.collection('entries').get();
    for (var i = 0; i < entries.docs.length; i += 400) {
      final batch = Backend.db.batch();
      for (final d in entries.docs.skip(i).take(400)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await partyRef.delete();
  }
}
