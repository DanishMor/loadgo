import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/transporter/party_statement.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/fleet/transporter_books_screen.dart';

import 'test_utils.dart';

/// MASTER-5 Task 37: a transporter sends each party what it owes.
void main() {
  const accounts = [
    TripAccount(bookingId: 'B2', partyId: 'p1', partyName: 'Anil Traders, Pune', revenuePaise: 2500000, receivedPaise: 1000000, driverPayPaise: 1800000),
    TripAccount(bookingId: 'B1', partyId: 'p1', partyName: 'Anil Traders, Pune', revenuePaise: 1200050, receivedPaise: 1200050),
    TripAccount(bookingId: 'B3', partyId: 'p2', partyName: 'Sharma', revenuePaise: 500000, receivedPaise: 0),
  ];
  final books = TransporterBooks.from(accounts);

  test('one party: its trips in booking order with exact paise and a total', () {
    final s = PartyStatement.of(books, 'p1')!;
    expect(s.trips.map((t) => t.bookingId), ['B1', 'B2']);
    final lines = s.toCsv().trim().split('\n');
    expect(lines.first, PartyStatement.csvHeader);
    expect(lines[1], 'B1,12000.50,12000.50,0.00');
    expect(lines[2], 'B2,25000.00,10000.00,15000.00');
    expect(lines.last, 'Total,37000.50,22000.50,15000.00');
    expect(PartyStatement.of(books, 'nobody'), isNull);
  });

  test('all parties: one line each, largest due first, quoted commas, a total', () {
    final lines = PartyStatement.allPartiesCsv(books).trim().split('\n');
    expect(lines[1], '"Anil Traders, Pune",2,37000.50,22000.50,15000.00');
    expect(lines[2], 'Sharma,1,5000.00,0.00,5000.00');
    expect(lines.last, 'Total,3,42000.50,22000.50,20000.00');
  });

  test('the PDF is produced', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await PartyStatement.of(books, 'p2')!.toPdf(company: 'Sharma Roadlines');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  testWidgets('the books screen has export for all parties and a statement button per party', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: TransporterBooksScreen(accounts: Stream.value(accounts)))));
    await settle(tester);
    expect(find.byKey(const ValueKey('booksExportAll')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('partyStatement_p1')));
    await settle(tester);
    expect(find.byKey(const ValueKey('partyCsv')), findsOneWidget);
    expect(find.byKey(const ValueKey('partyPdf')), findsOneWidget);
    expect(find.textContaining('Statement for Anil Traders'), findsOneWidget);
  });
}
