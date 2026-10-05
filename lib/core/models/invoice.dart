import 'package:cloud_firestore/cloud_firestore.dart';

/// Indian financial year label ("2026-27") of [d]: April to March.
String financialYear(DateTime d) {
  final start = d.month >= DateTime.april ? d.year : d.year - 1;
  return '$start-${((start + 1) % 100).toString().padLeft(2, '0')}';
}

/// "LG/2026-27/00042".
String invoiceSeriesNumber(String fy, int seq) => 'LG/$fy/${seq.toString().padLeft(5, '0')}';

/// `invoices/{bookingId}`: the GST invoice the driver issued. Amounts are a
/// snapshot in paise. The e-way bill fields are record only.
class TripInvoice {
  /// HSN/SAC for goods transport by road.
  static const defaultHsn = '996511';

  final String bookingId;
  final String issuerId;
  final String customerId;
  final String number;
  final int seq;
  final String fy;
  final num gstPercent;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int totalPaise;
  final String sellerName;
  final String sellerGstin;
  final String buyerName;
  final String buyerGstin;
  final String hsn;
  final String ewayBillNo;
  final DateTime? ewayValidUntil;
  final int? ewayDistanceKm;
  final DateTime? issuedAt;

  const TripInvoice({
    required this.bookingId,
    required this.issuerId,
    required this.customerId,
    required this.number,
    required this.seq,
    required this.fy,
    required this.gstPercent,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.totalPaise,
    required this.sellerName,
    this.sellerGstin = '',
    this.buyerName = '',
    this.buyerGstin = '',
    this.hsn = defaultHsn,
    this.ewayBillNo = '',
    this.ewayValidUntil,
    this.ewayDistanceKm,
    this.issuedAt,
  });

  factory TripInvoice.fromDoc(String id, Map<String, dynamic> d) => TripInvoice(
        bookingId: id,
        issuerId: d['issuerId'] as String? ?? '',
        customerId: d['customerId'] as String? ?? '',
        number: d['number'] as String? ?? '',
        seq: (d['seq'] as num? ?? 0).toInt(),
        fy: d['fy'] as String? ?? '',
        gstPercent: d['gstPercent'] as num? ?? 0,
        taxablePaise: (d['taxablePaise'] as num? ?? 0).toInt(),
        cgstPaise: (d['cgstPaise'] as num? ?? 0).toInt(),
        sgstPaise: (d['sgstPaise'] as num? ?? 0).toInt(),
        totalPaise: (d['totalPaise'] as num? ?? 0).toInt(),
        sellerName: d['sellerName'] as String? ?? '',
        sellerGstin: d['sellerGstin'] as String? ?? '',
        buyerName: d['buyerName'] as String? ?? '',
        buyerGstin: d['buyerGstin'] as String? ?? '',
        hsn: d['hsn'] as String? ?? defaultHsn,
        ewayBillNo: d['ewayBillNo'] as String? ?? '',
        ewayValidUntil: (d['ewayValidUntil'] as Timestamp?)?.toDate(),
        ewayDistanceKm: (d['ewayDistanceKm'] as num?)?.toInt(),
        issuedAt: (d['issuedAt'] as Timestamp?)?.toDate(),
      );
}
