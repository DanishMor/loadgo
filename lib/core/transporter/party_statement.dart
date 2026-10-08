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

  const PartyStatement(this.party, this.trips);

  /// The statement of [partyId] out of [books] (null when that party has no trip).
  static PartyStatement? of(TransporterBooks books, String partyId) {
    final trips = [for (final a in books.accounts) if (a.partyId == partyId) a]..sort((a, b) => a.bookingId.compareTo(b.bookingId));
    if (trips.isEmpty) return null;
    final p = books.parties.firstWhere((p) => p.partyId == partyId);
    return PartyStatement(p, trips);
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
    final doc = pw.Document(theme: theme, title: 'Statement ${party.partyName}');
    final name = party.partyName.isEmpty ? party.partyId : party.partyName;
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (c) => [
        pw.Text('Statement of account', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
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
