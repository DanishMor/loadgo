import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../enterprise/validators.dart';
import '../models/booking.dart';
import '../models/earnings.dart';
import '../models/invoice.dart';
import '../pricing/gst.dart';
import 'backend.dart';
import 'pricing_service.dart';

class InvoiceException implements Exception {
  /// 'not_delivered', 'not_driver', 'no_amount', 'seller', 'gstin', 'eway', 'exists'.
  final String reason;
  InvoiceException(this.reason);
  @override
  String toString() => 'InvoiceException($reason)';
}

/// GST invoices issued by the driver after delivery, numbered in a gapless
/// series per issuer and financial year. Record only: nothing is filed.
/// LATER(paid): GSP / e-way bill API.
class InvoiceService {
  InvoiceService._();

  static CollectionReference<Map<String, dynamic>> get _col => Backend.db.collection('invoices');

  static final _eway = RegExp(r'^\d{12}$');

  static Stream<TripInvoice?> watch(String bookingId) =>
      _col.doc(bookingId).snapshots().map((s) => s.exists ? TripInvoice.fromDoc(s.id, s.data()!) : null);

  /// Issues the invoice for [booking] as its driver. The number comes from a
  /// counter bumped in the same transaction.
  static Future<TripInvoice> issue({
    required Booking booking,
    required String sellerName,
    String sellerGstin = '',
    String buyerName = '',
    String buyerGstin = '',
    String ewayBillNo = '',
    DateTime? ewayValidUntil,
    int? ewayDistanceKm,
  }) async {
    final uid = Backend.requireUid();
    if (booking.status != BookingStatus.delivered) throw InvoiceException('not_delivered');
    if (booking.driverId != uid) throw InvoiceException('not_driver');
    final amount = booking.billAmountPaise;
    if (amount == null || amount <= 0) throw InvoiceException('no_amount');
    final seller = sellerName.trim();
    if (seller.isEmpty || seller.length > 80) throw InvoiceException('seller');
    final sg = sellerGstin.trim().toUpperCase(), bg = buyerGstin.trim().toUpperCase();
    if ((sg.isNotEmpty && !isValidGstinFormat(sg)) || (bg.isNotEmpty && !isValidGstinFormat(bg))) throw InvoiceException('gstin');
    final eway = ewayBillNo.trim();
    if (eway.isNotEmpty && !_eway.hasMatch(eway)) throw InvoiceException('eway');
    if (ewayDistanceKm != null && (ewayDistanceKm < 0 || ewayDistanceKm > 5000)) throw InvoiceException('eway');

    final fy = financialYear(EarningsSummary.deliveredAt(booking));
    final percent = PricingService.config.gstPercent;
    final gst = GstSplit.inclusive(amount, percent);
    final ref = _col.doc(booking.id);
    final series = Backend.db.collection('invoice_series').doc('${uid}_$fy');
    late TripInvoice made;
    await Backend.db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) throw InvoiceException('exists');
      final counter = await tx.get(series);
      final seq = counter.exists ? (counter.data()!['next'] as num).toInt() : 1;
      final number = invoiceSeriesNumber(fy, seq);
      tx.set(series, {'next': seq + 1, 'updatedAt': FieldValue.serverTimestamp()});
      tx.set(ref, {
        'bookingId': booking.id,
        'issuerId': uid,
        'customerId': booking.customerId,
        'driverId': booking.driverId,
        'seq': seq,
        'fy': fy,
        'number': number,
        'gstPercent': percent,
        'taxablePaise': gst.taxable,
        'cgstPaise': gst.cgst,
        'sgstPaise': gst.sgst,
        'totalPaise': gst.total,
        'sellerName': seller,
        if (sg.isNotEmpty) 'sellerGstin': sg,
        if (buyerName.trim().isNotEmpty) 'buyerName': buyerName.trim(),
        if (bg.isNotEmpty) 'buyerGstin': bg,
        'hsn': TripInvoice.defaultHsn,
        if (eway.isNotEmpty) 'ewayBillNo': eway,
        'ewayValidUntil': ?(ewayValidUntil == null ? null : Timestamp.fromDate(ewayValidUntil)),
        'ewayDistanceKm': ?ewayDistanceKm,
        'issuedAt': FieldValue.serverTimestamp(),
      });
      made = TripInvoice(
        bookingId: booking.id, issuerId: uid, customerId: booking.customerId, number: number, seq: seq, fy: fy, gstPercent: percent,
        taxablePaise: gst.taxable, cgstPaise: gst.cgst, sgstPaise: gst.sgst, totalPaise: gst.total, sellerName: seller,
      );
    });
    return made;
  }

  /// Record or correct the e-way bill details of an issued invoice.
  static Future<void> saveEway(String bookingId, {String ewayBillNo = '', DateTime? validUntil, int? distanceKm}) async {
    final eway = ewayBillNo.trim();
    if (eway.isNotEmpty && !_eway.hasMatch(eway)) throw InvoiceException('eway');
    await _col.doc(bookingId).update({
      if (eway.isNotEmpty) 'ewayBillNo': eway,
      'ewayValidUntil': ?(validUntil == null ? null : Timestamp.fromDate(validUntil)),
      'ewayDistanceKm': ?distanceKm,
    });
  }
}
