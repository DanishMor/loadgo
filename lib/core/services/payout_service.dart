import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/payout.dart';
import 'backend.dart';
import 'booking_service.dart';
import 'payment_service.dart';
import 'risk_service.dart';

class PayoutException implements Exception {
  /// `amount`, `too_much` or `open_request`.
  final String reason;
  const PayoutException(this.reason);

  @override
  String toString() => 'PayoutException($reason)';
}

/// Wallet payout requests. TODO(functions): check the balance and the
/// one-open-request limit on the server (the rules cannot sum the ledger).
class PayoutService {
  PayoutService._();

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('payouts');

  static Stream<List<Payout>> watchMine() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _col.where('driverId', isEqualTo: uid).snapshots().map(_sorted);
  }

  static Stream<List<Payout>> watchAll() => _col.snapshots().map(_sorted);

  static List<Payout> _sorted(QuerySnapshot<Map<String, dynamic>> s) {
    final list = [for (final d in s.docs) Payout.fromDoc(d.id, d.data())];
    list.sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
    return list;
  }

  /// The signed-in driver's current wallet figures.
  static Future<WalletBalances> balances() async {
    final uid = Backend.requireUid();
    final ledger = await PaymentService.watchLedger().first;
    final bookings = await BookingService.watchForDriver().first;
    final payouts = (await _col.where('driverId', isEqualTo: uid).get()).docs.map((d) => Payout.fromDoc(d.id, d.data()));
    return WalletBalances.of(ledger: ledger, bookings: bookings, payouts: payouts);
  }

  /// Asks for [amountPaise]; one open request at a time, at most what is
  /// available. Returns the new request id.
  static Future<String> request(int amountPaise) async {
    final uid = Backend.requireUid();
    await RiskService.ensureCanTransact();
    if (amountPaise < Payout.minPaise || amountPaise > Payout.maxPaise) throw const PayoutException('amount');
    final b = await balances();
    if (b.requested > 0) throw const PayoutException('open_request');
    if (amountPaise > b.available) throw const PayoutException('too_much');
    final ref = _col.doc();
    await ref.set({
      'driverId': uid,
      'amountPaise': amountPaise,
      'status': Payout.requested,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Admin: after paying outside the app, or turning the request down.
  static Future<void> setStatus(String id, String status) {
    assert(status == Payout.paid || status == Payout.rejected);
    return _col.doc(id).update({
      'status': status,
      'handledBy': Backend.requireUid(),
      'handledAt': FieldValue.serverTimestamp(),
    });
  }
}
