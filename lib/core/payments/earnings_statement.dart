import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../admin/admin_export.dart';
import '../app_info.dart';
import '../bilty/lr_pdf.dart' show LrFonts;
import '../models/booking.dart';
import '../models/ledger_entry.dart';

/// Which part of the wallet a statement covers.
enum StatementPeriod { thisMonth, lastMonth, financialYear, all }

extension StatementPeriodRange on StatementPeriod {
  /// First day (inclusive) and last day (inclusive) of the period; null = open end.
  (DateTime?, DateTime?) range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case StatementPeriod.thisMonth:
        return (DateTime(today.year, today.month, 1), DateTime(today.year, today.month + 1, 0));
      case StatementPeriod.lastMonth:
        return (DateTime(today.year, today.month - 1, 1), DateTime(today.year, today.month, 0));
      case StatementPeriod.financialYear:
        // India: 1 April to 31 March.
        final startYear = today.month >= 4 ? today.year : today.year - 1;
        return (DateTime(startYear, 4, 1), DateTime(startYear + 1, 3, 31));
      case StatementPeriod.all:
        return (null, null);
    }
  }
}

/// One trip in the statement.
class StatementRow {
  final DateTime? date;
  final String bookingId;
  final String route;
  final int earningPaise;

  /// Negative (a deduction), as in the ledger.
  final int commissionPaise;

  const StatementRow({required this.date, required this.bookingId, required this.route, required this.earningPaise, required this.commissionPaise});

  int get netPaise => earningPaise + commissionPaise;
}

/// A driver's earnings between two dates, built from the wallet ledger lines
/// and the bookings they belong to. Money is integer paise; the CSV and PDF
/// write it as rupees with two decimals. Records only: nothing is paid by it.
class EarningsStatement {
  final List<StatementRow> rows;
  final DateTime? from;
  final DateTime? to;

  const EarningsStatement(this.rows, {this.from, this.to});

  int get earningPaise => rows.fold(0, (a, r) => a + r.earningPaise);
  int get commissionPaise => rows.fold(0, (a, r) => a + r.commissionPaise);
  int get netPaise => earningPaise + commissionPaise;

  /// Ledger lines whose time falls inside [from]..[to] (whole days), grouped by
  /// booking, oldest first. A line without a time is left out of a dated period.
  factory EarningsStatement.build(Iterable<LedgerEntry> entries, Iterable<Booking> bookings, {DateTime? from, DateTime? to}) {
    final byBooking = {for (final b in bookings) b.id: b};
    final earn = <String, int>{};
    final comm = <String, int>{};
    final when = <String, DateTime>{};
    final start = from == null ? null : DateTime(from.year, from.month, from.day);
    final end = to == null ? null : DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
    for (final e in entries) {
      final at = e.createdAt;
      if ((start != null || end != null) && at == null) continue;
      if (start != null && at!.isBefore(start)) continue;
      if (end != null && !at!.isBefore(end)) continue;
      if (e.type == LedgerType.tripEarning) {
        earn[e.bookingId] = (earn[e.bookingId] ?? 0) + e.amountPaise;
      } else if (e.type == LedgerType.platformCommission) {
        comm[e.bookingId] = (comm[e.bookingId] ?? 0) + e.amountPaise;
      } else {
        continue;
      }
      if (at != null && (when[e.bookingId] == null || at.isBefore(when[e.bookingId]!))) when[e.bookingId] = at;
    }
    final ids = {...earn.keys, ...comm.keys}.toList()
      ..sort((a, b) {
        final x = when[a], y = when[b];
        if (x == null || y == null) return x == null ? (y == null ? a.compareTo(b) : 1) : -1;
        final c = x.compareTo(y);
        return c != 0 ? c : a.compareTo(b);
      });
    return EarningsStatement([
      for (final id in ids)
        StatementRow(
          date: when[id],
          bookingId: id,
          route: byBooking[id] == null ? '' : '${byBooking[id]!.pickup} - ${byBooking[id]!.drop}',
          earningPaise: earn[id] ?? 0,
          commissionPaise: comm[id] ?? 0,
        ),
    ], from: from, to: to);
  }

  /// Integer paise as `1234.50` (no float arithmetic, sign kept).
  static String rupees(int paise) {
    final neg = paise < 0;
    final a = paise.abs();
    final s = '${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
    return neg ? '-$s' : s;
  }

  static String _day(DateTime? d) => d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const csvHeader = 'date,booking,route,earning_inr,commission_inr,net_inr';

  String toCsv() {
    final lines = [csvHeader];
    for (final r in rows) {
      lines.add([_day(r.date), r.bookingId, r.route, rupees(r.earningPaise), rupees(r.commissionPaise), rupees(r.netPaise)].map(AdminExport.cell).join(','));
    }
    lines.add(['', '', 'Total', rupees(earningPaise), rupees(commissionPaise), rupees(netPaise)].map(AdminExport.cell).join(','));
    return '${lines.join('\n')}\n';
  }

  /// A one-or-more page PDF: heading, period, the table and the totals.
  Future<Uint8List> toPdf({String driverName = ''}) async {
    final fonts = await LrFonts.load();
    final theme = pw.ThemeData.withFont(base: fonts.first, bold: fonts.first, fontFallback: fonts.sublist(1));
    final doc = pw.Document(theme: theme, title: '${AppInfo.name} earnings statement');
    final period = from == null && to == null ? 'All time' : '${_day(from)} to ${_day(to)}';
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (c) => [
        pw.Text('${AppInfo.name} earnings statement', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        if (driverName.trim().isNotEmpty) pw.Text(driverName.trim()),
        pw.Text('Period: $period', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const ['Date', 'Route', 'Earning (INR)', 'Commission (INR)', 'Net (INR)'],
          data: [
            for (final r in rows) [_day(r.date), r.route, rupees(r.earningPaise), rupees(r.commissionPaise), rupees(r.netPaise)],
            ['', 'Total', rupees(earningPaise), rupees(commissionPaise), rupees(netPaise)],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
        ),
        pw.SizedBox(height: 14),
        pw.Text('A record of the wallet lines kept in the ${AppInfo.name} app. No money moves through the app; this is not a tax document.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ));
    return doc.save();
  }
}
