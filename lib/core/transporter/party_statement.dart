import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../admin/admin_export.dart';
import '../app_info.dart';
import '../bilty/lr_pdf.dart' show LrFonts;
import '../payments/earnings_statement.dart' show EarningsStatement;
import 'transporter_logic.dart';

/// What a transporter sends a party (MASTER-5 Task 37): every trip booked for
/// that party with what it costs, what has come in and what is still due; or
/// one line per party for the whole book. Integer paise; the files show
/// rupees with two decimals. A record, not a tax invoice.
class PartyStatement {
  final PartyBalance party;
  final List<TripAccount> trips;

  /// `2026-10` when the statement covers one month, else null (all trips).
  final String? month;

  const PartyStatement(this.party, this.trips, {this.month});

  /// The statement of [partyId] out of [books] (null when that party has no
  /// trip). With [month] (`2026-10`) only that month's trips and their totals
  /// (null when the party has none that month).
  static PartyStatement? of(TransporterBooks books, String partyId, {String? month}) {
    final trips = [
      for (final a in books.accounts)
        if (a.partyId == partyId && (month == null || a.month == month)) a,
    ]..sort((a, b) => a.bookingId.compareTo(b.bookingId));
    if (trips.isEmpty) return null;
    final base = books.parties.firstWhere((p) => p.partyId == partyId);
    final p = month == null
        ? base
        : PartyBalance(partyId, base.partyName, trips.length, trips.fold(0, (s, a) => s + a.revenuePaise), trips.fold(0, (s, a) => s + a.receivedPaise));
    return PartyStatement(p, trips, month: month);
  }

  /// The months (newest first) in which [partyId] has trips; lines with no date are left out.
  static List<String> monthsOf(TransporterBooks books, String partyId) =>
      ({for (final a in books.accounts) if (a.partyId == partyId && a.month.isNotEmpty) a.month}.toList()..sort((a, b) => b.compareTo(a)));

  /// One line per month for [partyId]: trips, amount, received and due, with a total row.
  static String monthlyCsv(TransporterBooks books, String partyId) {
    final lines = ['month,trips,revenue_inr,received_inr,due_inr'];
    var trips = 0, revenue = 0, received = 0;
    for (final m in monthsOf(books, partyId).reversed) {
      final s = of(books, partyId, month: m)!;
      lines.add([m, s.party.trips, _r(s.party.revenuePaise), _r(s.party.receivedPaise), _r(s.party.duePaise)].map(AdminExport.cell).join(','));
      trips += s.party.trips;
      revenue += s.party.revenuePaise;
      received += s.party.receivedPaise;
    }
    final due = revenue > received ? revenue - received : 0;
    lines.add(['Total', trips, _r(revenue), _r(received), _r(due)].map(AdminExport.cell).join(','));
    return '${lines.join('\n')}\n';
  }

  static String _r(int paise) => EarningsStatement.rupees(paise);

  static const csvHeader = 'booking,revenue_inr,received_inr,due_inr';

  String toCsv() {
    final lines = [csvHeader];
    for (final t in trips) {
      lines.add([t.bookingId, _r(t.revenuePaise), _r(t.receivedPaise), _r(t.dueFromPartyPaise)].map(AdminExport.cell).join(','));
    }
    lines.add(['Total', _r(party.revenuePaise), _r(party.receivedPaise), _r(party.duePaise)].map(AdminExport.cell).join(','));
    return '${lines.join('\n')}\n';
  }

  Future<Uint8List> toPdf({String company = ''}) async {
    final fonts = await LrFonts.load();
    final theme = pw.ThemeData.withFont(base: fonts.first, bold: fonts.first, fontFallback: fonts.sublist(1));
    final doc = pw.Document(theme: theme, title: 'Statement ${party.partyName}${month == null ? '' : ' $month'}');
    final name = party.partyName.isEmpty ? party.partyId : party.partyName;
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (c) => [
        pw.Text(month == null ? 'Statement of account' : 'Statement of account: $month', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        if (company.trim().isNotEmpty) pw.Text('From: ${company.trim()}'),
        pw.Text('To: $name'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const ['Trip', 'Amount (INR)', 'Received (INR)', 'Due (INR)'],
          data: [
            for (final t in trips) [t.bookingId, _r(t.revenuePaise), _r(t.receivedPaise), _r(t.dueFromPartyPaise)],
            ['Total', _r(party.revenuePaise), _r(party.receivedPaise), _r(party.duePaise)],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
        ),
        pw.SizedBox(height: 14),
        pw.Text('A statement from the books kept in the ${AppInfo.name} app. No money moves through the app; this is not a tax invoice.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ));
    return doc.save();
  }

  /// One line per party for the whole book.
  static String allPartiesCsv(TransporterBooks books) {
    final lines = ['party,trips,revenue_inr,received_inr,due_inr'];
    for (final p in books.parties) {
      lines.add([p.partyName.isEmpty ? p.partyId : p.partyName, p.trips, _r(p.revenuePaise), _r(p.receivedPaise), _r(p.duePaise)].map(AdminExport.cell).join(','));
    }
    lines.add(['Total', books.accounts.length, _r(books.revenuePaise), _r(books.parties.fold(0, (s, p) => s + p.receivedPaise)), _r(books.dueFromPartiesPaise)].map(AdminExport.cell).join(','));
    return '${lines.join('\n')}\n';
  }
}
