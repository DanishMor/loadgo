import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/claim.dart';
import 'backend.dart';

class ClaimException implements Exception {
  /// 'not_ready' (booking has not reached unloading), 'already', 'description', 'amount', 'closed'.
  final String reason;
  ClaimException(this.reason);
  @override
  String toString() => 'ClaimException($reason)';
}

/// Damage / dispute claims. Parties open one per booking and exchange
/// messages; admins review and resolve. TODO(functions): notify the other party.
class ClaimService {
  ClaimService._();

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('claims');

  static String claimId(String bookingId, String uid) => '${bookingId}_$uid';

  static bool canOpen(Booking b) => b.status == BookingStatus.unloading || b.status == BookingStatus.delivered;

  /// The signed-in customer or driver opens a claim on [booking].
  static Future<String> open({required Booking booking, required String type, required String description, int? amountPaise}) async {
    final uid = Backend.requireUid();
    if (uid != booking.customerId && uid != booking.driverId) throw StateError('Not part of this booking');
    if (!canOpen(booking)) throw ClaimException('not_ready');
    final text = description.trim();
    if (text.length < Claim.minDescription || text.length > 1000) throw ClaimException('description');
    if (!ClaimType.all.contains(type)) throw ArgumentError.value(type, 'type');
    if (amountPaise != null && (amountPaise < 0 || amountPaise > Claim.maxAmountPaise)) throw ClaimException('amount');
    final ref = _col.doc(claimId(booking.id, uid));
    if ((await ref.get()).exists) throw ClaimException('already');
    final batch = Backend.db.batch();
    batch.set(ref, {
      'bookingId': booking.id,
      'customerId': booking.customerId,
      'driverId': booking.driverId,
      'openedBy': uid,
      'type': type,
      'description': text,
      'amountPaise': ?amountPaise,
      'status': ClaimStatus.open,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('events').doc(), _event(uid, uid == booking.customerId ? 'customer' : 'driver', 'opened', text));
    await batch.commit();
    return ref.id;
  }

  static Map<String, Object?> _event(String by, String role, String kind, String text) =>
      {'by': by, 'role': role, 'kind': kind, 'text': text, 'createdAt': FieldValue.serverTimestamp()};

  /// A message on the timeline, from a party (while open) or an admin.
  static Future<void> addMessage(Claim claim, String text, {bool admin = false}) async {
    final uid = Backend.requireUid();
    final t = text.trim();
    if (t.isEmpty || t.length > 1000) throw ArgumentError('A message is 1 to 1000 characters');
    if (!admin && claim.isClosed) throw ClaimException('closed');
    final role = admin ? 'admin' : (uid == claim.customerId ? 'customer' : 'driver');
    await _col.doc(claim.id).collection('events').add(_event(uid, role, 'message', t));
  }

  static Stream<Claim?> watch(String id) => _col.doc(id).snapshots().map((s) => s.exists ? Claim.fromDoc(s.id, s.data()!) : null);

  static Stream<List<ClaimEvent>> watchEvents(String id) => _col.doc(id).collection('events').snapshots().map((s) {
        final list = [for (final d in s.docs) ClaimEvent.fromDoc(d.id, d.data())];
        list.sort((a, b) => (a.createdAt ?? DateTime(3000)).compareTo(b.createdAt ?? DateTime(3000)));
        return list;
      });

  /// Claims the signed-in user is a party to (as customer or as driver).
  static Stream<List<Claim>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    final latest = <String, List<Claim>>{};
    final subs = <StreamSubscription>[];
    late StreamController<List<Claim>> out;
    void emit() {
      if (latest.length < 2) return; // wait until both queries answered
      final all = {for (final c in latest.values.expand((x) => x)) c.id: c}.values.toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
      out.add(all);
    }

    out = StreamController<List<Claim>>(
      onListen: () {
        for (final field in ['customerId', 'driverId']) {
          subs.add(_col.where(field, isEqualTo: uid).snapshots().listen((s) {
            latest[field] = [for (final d in s.docs) Claim.fromDoc(d.id, d.data())];
            emit();
          }, onError: out.addError));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  /// Claims of one booking among those the user can see.
  static Stream<List<Claim>> watchForBooking(String bookingId) =>
      watchMine().map((l) => [for (final c in l) if (c.bookingId == bookingId) c]);

  // ---- admin ----

  static Stream<List<Claim>> watchAll() => _col.limit(300).snapshots().map((s) {
        final list = [for (final d in s.docs) Claim.fromDoc(d.id, d.data())];
        list.sort((a, b) {
          int rank(Claim c) => c.isClosed ? 1 : 0;
          final r = rank(a).compareTo(rank(b));
          return r != 0 ? r : (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000));
        });
        return list;
      });

  static Future<void> startReview(Claim claim) async {
    final uid = Backend.requireUid();
    final batch = Backend.db.batch();
    batch.update(_col.doc(claim.id), {'status': ClaimStatus.underReview, 'updatedAt': FieldValue.serverTimestamp()});
    batch.set(_col.doc(claim.id).collection('events').doc(), _event(uid, 'admin', 'status', ClaimStatus.underReview));
    await batch.commit();
  }

  static Future<void> resolve(Claim claim, {required String outcome, String note = '', int? awardedPaise}) async {
    final uid = Backend.requireUid();
    if (!ClaimOutcome.all.contains(outcome)) throw ArgumentError.value(outcome, 'outcome');
    if (awardedPaise != null && (awardedPaise < 0 || awardedPaise > Claim.maxAmountPaise)) throw ClaimException('amount');
    final n = note.trim();
    final batch = Backend.db.batch();
    batch.update(_col.doc(claim.id), {
      'status': ClaimStatus.resolved,
      'outcome': outcome,
      'awardedPaise': ?awardedPaise,
      if (n.isNotEmpty) 'resolutionNote': n,
      'resolvedBy': uid,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_col.doc(claim.id).collection('events').doc(), _event(uid, 'admin', 'resolution', n.isEmpty ? outcome : '$outcome: $n'));
    await batch.commit();
  }
}
