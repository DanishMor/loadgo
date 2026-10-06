import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/driver_extras.dart';
import '../models/ledger_entry.dart';
import '../identity/profile_extras.dart';
import '../payments/payment_logic.dart';
import 'backend.dart';
import 'notification_service.dart';
import '../widgets/common.dart' show formatPaise;
import 'pricing_service.dart';

/// Payment *records* between customer and driver: the customer marks a
/// booking paid, the driver confirms receipt, and the driver's ledger gets
/// the trip earning and the platform commission. No money moves through
/// LoadGo. LATER(paid): payment gateway, payouts.
/// TODO(functions): compute commission and payouts server-side.
class PaymentService {
  PaymentService._();

  static CollectionReference<Map<String, dynamic>> get _ledger => Backend.db.collection('ledger');

  /// Platform commission (negative paise) on [amountPaise]; Pro drivers pay
  /// the lower `proCommissionPercent`.
  static int commissionFor(int amountPaise, {bool pro = false}) {
    final c = PricingService.config;
    final percent = pro ? c.proCommissionPercent : c.commissionPercent;
    return -(amountPaise * (percent * 100).round() / 10000).round();
  }

  /// Customer: "I have paid [amountPaise]".
  static Future<void> markPaid(Booking b, int amountPaise) {
    if (amountPaise <= 0 || amountPaise > 100000000) throw ArgumentError.value(amountPaise, 'amountPaise');
    if (b.paymentStatus != PaymentStatus.pending) throw StateError('Already marked');
    final batch = Backend.db.batch();
    batch.update(Backend.db.collection('bookings').doc(b.id), {
      'paymentStatus': PaymentStatus.customerMarkedPaid,
      'paidAmountPaise': amountPaise,
      'paymentMarkedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    NotificationService.addInBatch(
      batch,
      userId: b.driverId,
      type: NotificationType.paymentMarked,
      message: '${b.pickup} → ${b.drop}: ${formatPaise(amountPaise)}',
      relatedId: b.id,
    );
    return batch.commit();
  }

  /// Driver: "I received it" — also writes the ledger lines.
  static Future<void> confirmReceived(Booking b) async {
    final uid = Backend.requireUid();
    if (b.driverId != uid || b.paymentStatus != PaymentStatus.customerMarkedPaid || b.paidAmountPaise == null) {
      throw StateError('Nothing to confirm');
    }
    final amount = b.paidAmountPaise!;
    final profile = (await Backend.db.collection('users').doc(uid).get()).data();
    final pro = DriverPlan.isPro(profile, DateTime.now());
    final batch = Backend.db.batch();
    batch.update(Backend.db.collection('bookings').doc(b.id), {
      'paymentStatus': PaymentStatus.driverConfirmed,
      'paymentConfirmedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    void line(String type, int paise) => batch.set(_ledger.doc('${b.id}_$type'), {
          'driverId': uid,
          'bookingId': b.id,
          'type': type,
          'amountPaise': paise,
          'createdAt': FieldValue.serverTimestamp(),
        });
    NotificationService.addInBatch(
      batch,
      userId: b.customerId,
      type: NotificationType.paymentConfirmed,
      message: '${b.pickup} → ${b.drop}',
      relatedId: b.id,
    );
    line(LedgerType.tripEarning, amount);
    line(LedgerType.platformCommission, commissionFor(amount, pro: pro));
    await batch.commit();
  }

  /// Customer: "I paid an advance of [paise]" (PAY3). Once per booking while it
  /// is open; the rest is the balance, marked paid after delivery as before.
  static Future<void> recordAdvance(Booking b, int paise) {
    if (!validAdvance(paise, b.billAmountPaise)) throw ArgumentError.value(paise, 'paise');
    if (b.advancePaise != null) throw StateError('Advance already recorded');
    if (b.paymentStatus != PaymentStatus.pending || b.status == BookingStatus.cancelled || b.status == BookingStatus.delivered) {
      throw StateError('Advance not possible now');
    }
    return Backend.db.collection('bookings').doc(b.id).update({
      'advancePaise': paise,
      'advanceMarkedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Driver: "I received the advance".
  static Future<void> confirmAdvance(Booking b) {
    if (b.driverId != Backend.requireUid() || b.advancePaise == null || b.advanceConfirmedAt != null) throw StateError('No advance to confirm');
    return Backend.db.collection('bookings').doc(b.id).update({
      'advanceConfirmedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Driver: shares the UPI id of their payout profile on this booking so the
  /// customer can open a UPI payment link (P0-06, PAY1). Returns false when
  /// the profile has no valid UPI id.
  static Future<bool> shareUpiId(Booking b) async {
    final uid = Backend.requireUid();
    if (b.driverId != uid) throw StateError('Not your trip');
    final profile = (await Backend.db.collection('users').doc(uid).get()).data() ?? const <String, dynamic>{};
    final upi = ProfileExtras.fromProfile(profile).upiId.trim();
    if (!isValidUpiId(upi)) return false;
    await Backend.db.collection('bookings').doc(b.id).update({'payUpiId': upi, 'updatedAt': FieldValue.serverTimestamp()});
    return true;
  }

  /// The signed-in driver's ledger, newest first.
  static Stream<List<LedgerEntry>> watchLedger() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _ledger.where('driverId', isEqualTo: uid).snapshots().map((s) {
      final list = s.docs.map(LedgerEntry.fromDoc).toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
      return list;
    });
  }
}
