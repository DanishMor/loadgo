import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_info.dart';
import '../bilty/lr_pdf.dart' show LrFonts;
import '../pricing/fare_calculator.dart';
import '../pricing/price_transparency.dart';
import '../widgets/common.dart' show formatPaise, formatNum;

/// E31 (flag quoteShare): what a shared quote or booking says. Never a phone number, an OTP, a person's id or a
/// document id the reader could use; only the route, the goods, the truck, the date and the price lines.
class QuoteSummary {
  final String title;
  final String pickup;
  final String drop;
  final String goods;
  final num? weightTons;
  final String vehicle;
  final String when;

  /// The fare lines (label, paise) and the total; or only [pricePaise] for an agreed price.
  final List<(String, int)> lines;
  final int pricePaise;

  /// A short reference the customer can quote on the phone (the last 6 characters of the booking id), or empty.
  final String reference;

  const QuoteSummary({
    required this.title,
    required this.pickup,
    required this.drop,
    required this.vehicle,
    required this.pricePaise,
    this.goods = '',
    this.weightTons,
    this.when = '',
    this.lines = const [],
    this.reference = '',
  });

  /// The fare lines of [f] labelled by [label] (a words key per PriceTransparency charge key).
  static List<(String, int)> linesOf(FareBreakdown f, String Function(String chargeKey) label) => [for (final (k, p) in PriceTransparency.lines(f)) (label(k), p)];

  static String refOf(String id) => id.length <= 6 ? id.toUpperCase() : id.substring(id.length - 6).toUpperCase();

  /// Plain text for chat apps. [labels] gives the translated words: route, goods, vehicle, when, total, ref, note.
  String asText(Map<String, String> labels) {
    final b = StringBuffer()
      ..writeln('$title · ${AppInfo.name}')
      ..writeln('${labels['route']}: $pickup → $drop');
    if (goods.isNotEmpty) b.writeln('${labels['goods']}: $goods${weightTons == null ? '' : ', ${formatNum(weightTons!)} T'}');
    b.writeln('${labels['vehicle']}: $vehicle');
    if (when.isNotEmpty) b.writeln('${labels['when']}: $when');
    for (final (l, p) in lines) {
      b.writeln('$l: ${formatPaise(p)}');
    }
    b.writeln('${labels['total']}: ${formatPaise(pricePaise)}');
    if (reference.isNotEmpty) b.writeln('${labels['ref']}: $reference');
    b.write(labels['note'] ?? '');
    return b.toString().trimRight();
  }

  /// A one-page PDF with the same words, printed with the app's Indian-script fonts.
  Future<Uint8List> toPdf(Map<String, String> labels, {List<pw.Font>? fonts}) async {
    final f = fonts ?? await LrFonts.load();
    final theme = pw.ThemeData.withFont(base: f.first, bold: f.first, italic: f.first, boldItalic: f.first, fontFallback: f.sublist(1));
    final doc = pw.Document(title: title, author: AppInfo.name, theme: theme);
    pw.Widget row(String k, String v, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: pw.Text(k, style: pw.TextStyle(fontSize: strong ? 13 : 11, color: strong ? PdfColors.black : PdfColors.grey700))),
            pw.Text(v, style: pw.TextStyle(fontSize: strong ? 13 : 11)),
          ]),
        );
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(AppInfo.name, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(title, style: const pw.TextStyle(fontSize: 18)),
        pw.SizedBox(height: 12),
        row(labels['route'] ?? '', '$pickup → $drop'),
        if (goods.isNotEmpty) row(labels['goods'] ?? '', '$goods${weightTons == null ? '' : ', ${formatNum(weightTons!)} T'}'),
        row(labels['vehicle'] ?? '', vehicle),
        if (when.isNotEmpty) row(labels['when'] ?? '', when),
        pw.Divider(),
        for (final (l, p) in lines) row(l, formatPaise(p)),
        row(labels['total'] ?? '', formatPaise(pricePaise), strong: true),
        if (reference.isNotEmpty) row(labels['ref'] ?? '', reference),
        pw.SizedBox(height: 12),
        pw.Text(labels['note'] ?? '', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ]),
    ));
    return doc.save();
  }
}
