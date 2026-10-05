import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/booking.dart';
import '../models/invoice.dart';

String _rupees(int paise) {
  final r = paise ~/ 100, p = paise % 100;
  return 'Rs ${r.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}.${p.toString().padLeft(2, '0')}';
}

String _date(DateTime? d) => d == null ? '-' : '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

/// A4 GST invoice as PDF bytes. The built-in PDF font has no Indian scripts,
/// so the document is in English with "Rs" for the rupee sign.
Future<Uint8List> buildInvoicePdf(TripInvoice inv, Booking b) async {
  final doc = pw.Document(title: inv.number, author: 'LoadGo');
  pw.Widget row(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 120, child: pw.Text(k, style: const pw.TextStyle(color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(v)),
        ]),
      );
  final half = (inv.gstPercent / 2).toStringAsFixed(inv.gstPercent % 2 == 0 ? 0 : 1);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('TAX INVOICE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text(inv.number, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Text('Issued via LoadGo on ${_date(inv.issuedAt)}', style: const pw.TextStyle(color: PdfColors.grey700)),
      pw.Divider(),
      row('Seller (transporter)', inv.sellerName),
      if (inv.sellerGstin.isNotEmpty) row('Seller GSTIN', inv.sellerGstin),
      row('Buyer', inv.buyerName.isEmpty ? '-' : inv.buyerName),
      if (inv.buyerGstin.isNotEmpty) row('Buyer GSTIN', inv.buyerGstin),
      row('HSN / SAC', '${inv.hsn} (goods transport by road)'),
      pw.Divider(),
      row('From', b.pickup),
      row('To', b.drop),
      row('Cargo', '${b.cargoType}, ${b.weight} t'),
      row('Vehicle', b.vehicleNumber),
      row('LR number', b.lrNumber),
      row('E-way bill', inv.ewayBillNo.isEmpty ? '-' : inv.ewayBillNo),
      if (inv.ewayValidUntil != null) row('E-way valid until', _date(inv.ewayValidUntil)),
      if (inv.ewayDistanceKm != null) row('Distance', '${inv.ewayDistanceKm} km'),
      pw.Divider(),
      row('Taxable value', _rupees(inv.taxablePaise)),
      row('CGST $half%', _rupees(inv.cgstPaise)),
      row('SGST $half%', _rupees(inv.sgstPaise)),
      pw.Divider(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Invoice total', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.Text(_rupees(inv.totalPaise), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.SizedBox(height: 18),
      pw.Text('Record generated in the LoadGo app. The e-way bill details are recorded only and are not filed on the GST portal.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    ]),
  ));
  return doc.save();
}

/// Opens the system share sheet with the PDF.
Future<void> shareInvoicePdf(TripInvoice inv, Booking b) async {
  final bytes = await buildInvoicePdf(inv, b);
  await Printing.sharePdf(bytes: bytes, filename: '${inv.number.replaceAll('/', '-')}.pdf');
}
