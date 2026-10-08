import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_info.dart';
import '../l10n/l10n.dart';
import 'lr_copy_view.dart';

/// The Noto fonts bundled in assets/fonts: one per script, tried in turn for
/// every character so Hindi, Kannada, Tamil, Telugu, Gujarati, Bengali,
/// Punjabi and Urdu / Kashmiri text never turns into empty boxes.
/// (The pdf package draws Indic scripts without conjunct shaping: the letters
/// are all there, a few joined forms are drawn side by side.)
class LrFonts {
  LrFonts._();

  static const files = [
    'NotoSans-Regular.ttf',
    'NotoSansDevanagari-Regular.ttf',
    'NotoSansKannada-Regular.ttf',
    'NotoSansTamil-Regular.ttf',
    'NotoSansTelugu-Regular.ttf',
    'NotoSansGujarati-Regular.ttf',
    'NotoSansBengali-Regular.ttf',
    'NotoSansGurmukhi-Regular.ttf',
    'NotoNaskhArabic-Regular.ttf',
  ];

  static List<pw.Font>? _cache;

  static Future<List<pw.Font>> load() async => _cache ??= [
        for (final f in files) pw.Font.ttf(await rootBundle.load('assets/fonts/$f')),
      ];

  static void clearCache() => _cache = null;
}

class LrPdfInput {
  /// Snapshot of the copy (from `LrVisibility.snapshot`).
  final Map<String, Object> fields;
  final String copy;
  final String issuerRole;
  final AppLanguage language;

  /// Link in the verify QR code (shows only LR no, route, status, issuer).
  final String verifyUrl;
  final String issuerName;
  final bool delivered;
  final DateTime generatedAt;

  /// Big diagonal text (the offline inspection copy, Task 71).
  final String? watermark;

  /// Extra line under the heading (the driver the inspection copy is for).
  final String? subtitle;
  const LrPdfInput({
    required this.fields,
    required this.copy,
    required this.issuerRole,
    required this.language,
    required this.verifyUrl,
    required this.issuerName,
    required this.delivered,
    required this.generatedAt,
    this.watermark,
    this.subtitle,
  });
}

String _stamp(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// A4 LR as PDF bytes: heading, copy type, the rows of the copy, signature,
/// delivery-proof line and the verify QR code.
Future<Uint8List> buildLrPdf(LrPdfInput i) async {
  final fonts = await LrFonts.load();
  final theme = pw.ThemeData.withFont(base: fonts.first, bold: fonts.first, fontFallback: fonts.sublist(1));
  String t(String k) => trLang(k, i.language);
  // The bundled fonts have no arrow glyph.
  final rows = [for (final r in lrRows(i.fields)) LrRow(r.labelKey, r.value.replaceAll('→', '>'))];
  final doc = pw.Document(title: '${i.fields['lrNo']}', author: AppInfo.name, theme: theme);
  pw.Widget row(LrRow r) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 150, child: pw.Text(t(r.labelKey), style: const pw.TextStyle(color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(r.value)),
        ]),
      );
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => pw.Stack(children: [
      if (i.watermark != null)
        pw.Positioned.fill(
          child: pw.Center(
            child: pw.Transform.rotate(
              angle: 0.6,
              child: pw.Text(i.watermark!, style: const pw.TextStyle(fontSize: 56, color: PdfColors.grey300)),
            ),
          ),
        ),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Expanded(child: pw.Text(t(lrHeadingKey(i.issuerRole)), style: const pw.TextStyle(fontSize: 18))),
          pw.Text(t(lrCopyKey(i.copy)), style: const pw.TextStyle(fontSize: 14)),
        ]),
        pw.Text('${AppInfo.name}  •  ${_stamp(i.generatedAt)}', style: const pw.TextStyle(color: PdfColors.grey700)),
        if (i.subtitle != null) pw.Text(i.subtitle!),
        pw.Divider(),
        for (final r in rows) row(r),
        pw.Divider(),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('${t('blSignedBy')}: ${i.issuerName}'),
            pw.SizedBox(height: 4),
            pw.Text('${t('blPodLine')}: ${i.delivered ? t('blPodVerified') : t('blPodPending')}'),
          ]),
          pw.Column(children: [
            pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: i.verifyUrl, width: 84, height: 84, drawText: false),
            pw.SizedBox(height: 2),
            pw.Text(t('blVerifyLine'), style: const pw.TextStyle(fontSize: 8)),
          ]),
        ]),
      ]),
    ]),
  ));
  return doc.save();
}
