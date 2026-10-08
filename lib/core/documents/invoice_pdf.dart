import '../app_info.dart';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../bilty/lr_pdf.dart' show LrFonts;
import 'amount_words.dart';
import '../models/booking.dart';
import '../models/invoice.dart';

/// Rupees in the Indian way of grouping: 12,34,567.89.
String _rupees(int paise) {
  final r = paise ~/ 100, p = paise % 100;
  final digits = r.toString();
  final last3 = digits.length <= 3 ? digits : digits.substring(digits.length - 3);
  final rest = digits.length <= 3 ? '' : digits.substring(0, digits.length - 3);
  final grouped = rest.isEmpty ? last3 : '${rest.replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+$)'), (m) => '${m[1]},')},$last3';
  return '\u20B9$grouped.${p.toString().padLeft(2, '0')}';
}

@visibleForTesting
String invoiceRupees(int paise) => _rupees(paise);

String _date(DateTime? d) => d == null ? '-' : '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

/// A4 GST invoice as PDF bytes (MASTER-5 Task 36 polish): the bundled Noto
/// fonts so names in any Indian script print, the rupee sign, the amounts in
/// a right-aligned table, the total in words and a signature line. The text
/// itself stays in English, as a tax document usually is.
Future<Uint8List> buildInvoicePdf(TripInvoice inv, Booking b) async {
  final fonts = await LrFonts.load();
  final theme = pw.ThemeData.withFont(base: fonts.first, bold: fonts.first, italic: fonts.first, boldItalic: fonts.first, fontFallback: fonts.sublist(1));
  final doc = pw.Document(title: inv.number, author: AppInfo.name, theme: theme);
  pw.Widget row(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 120, child: pw.Text(k, style: const pw.TextStyle(color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(v)),
        ]),
      );
  pw.Widget amountRow(String k, int paise, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(k, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: bold ? 13 : 11)),
          pw.Text(_rupees(paise), style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: bold ? 14 : 11)),
        ]),
      );
  pw.Widget section(String t) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 4),
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        color: PdfColors.grey200,
        child: pw.Text(t, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
      );
  final half = (inv.gstPercent / 2).toStringAsFixed(inv.gstPercent % 2 == 0 ? 0 : 1);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('TAX INVOICE', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(inv.number, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('Date: ${_date(inv.issuedAt)}', style: const pw.TextStyle(color: PdfColors.grey700)),
        ]),
      ]),
      pw.Container(height: 2, color: PdfColors.blue900, margin: const pw.EdgeInsets.only(top: 6)),
      section('SELLER (TRANSPORTER)'),
      row('Name', inv.sellerName),
      if (inv.sellerGstin.isNotEmpty) row('GSTIN', inv.sellerGstin),
      section('BUYER'),
      row('Name', inv.buyerName.isEmpty ? '-' : inv.buyerName),
      if (inv.buyerGstin.isNotEmpty) row('GSTIN', inv.buyerGstin),
      section('TRIP'),
      row('From', b.pickup),
      row('To', b.drop),
      row('Cargo', '${b.cargoType}, ${b.weight} t'),
      row('Vehicle', b.vehicleNumber),
      row('LR number', b.lrNumber),
      row('HSN / SAC', '${inv.hsn} (goods transport by road)'),
      row('E-way bill', inv.ewayBillNo.isEmpty ? '-' : inv.ewayBillNo),
      if (inv.ewayValidUntil != null) row('E-way valid until', _date(inv.ewayValidUntil)),
      if (inv.ewayDistanceKm != null) row('Distance', '${inv.ewayDistanceKm} km'),
      section('AMOUNT'),
      amountRow('Taxable value', inv.taxablePaise),
      amountRow('CGST $half%', inv.cgstPaise),
      amountRow('SGST $half%', inv.sgstPaise),
      pw.Divider(),
      amountRow('Invoice total', inv.totalPaise, bold: true),
      pw.SizedBox(height: 4),
      pw.Text(amountInWords(inv.totalPaise), style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic)),
      pw.Spacer(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(height: 28),
          pw.Container(width: 170, height: 1, color: PdfColors.grey600),
          pw.Text('For ${inv.sellerName}', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Authorised signatory', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ]),
      ]),
      pw.SizedBox(height: 14),
      pw.Text('Record generated in the ${AppInfo.name} app. The e-way bill details are recorded only and are not filed on the GST portal.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
    ]),
  ));
  return doc.save();
}

/// Opens the system share sheet with the PDF.
Future<void> shareInvoicePdf(TripInvoice inv, Booking b) async {
  final bytes = await buildInvoicePdf(inv, b);
  await Printing.sharePdf(bytes: bytes, filename: '${inv.number.replaceAll('/', '-')}.pdf');
}
