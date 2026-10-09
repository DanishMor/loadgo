import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/transporter/party_statement.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/fleet/transporter_books_screen.dart';

import 'test_utils.dart';

/// MASTER-6 Task 30: party statements by month.
void main() {
  final accounts = [
    TripAccount(bookingId: 'B1', partyId: 'p1', partyName: 'Anil Traders', revenuePaise: 1000000, receivedPaise: 1000000, at: DateTime(2026, 8, 20)),
    TripAccount(bookingId: 'B2', partyId: 'p1', partyName: 'Anil Traders', revenuePaise: 2000000, receivedPaise: 500000, at: DateTime(2026, 9, 3)),
    TripAccount(bookingId: 'B3', partyId: 'p1', partyName: 'Anil Traders', revenuePaise: 3000000, receivedPaise: 0, at: DateTime(2026, 9, 28)),
    const TripAccount(bookingId: 'B4', partyId: 'p1', partyName: 'Anil Traders', revenuePaise: 400000, receivedPaise: 0), // no date
    TripAccount(bookingId: 'B5', partyId: 'p2', partyName: 'Sharma', revenuePaise: 700000, receivedPaise: 700000, at: DateTime(2026, 9, 9)),
  ];
  final books = TransporterBooks.from(accounts);

  test('a line says which month it belongs to; an undated line has none', () {
    expect(accounts[0].month, '2026-08');
    expect(accounts[1].month, '2026-09');
    expect(accounts[3].month, '');
    expect(TripAccount.fromMap('x', {'partyId': 'p', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)), 'updatedAt': Timestamp.fromDate(DateTime(2026, 11, 1))}).month, '2026-10'); // the day it was made, not the last save
    expect(TripAccount.fromMap('x', {'partyId': 'p', 'updatedAt': Timestamp.fromDate(DateTime(2026, 11, 1))}).month, '2026-11'); // older lines
  });

  test('months of a party: newest first, undated left out', () {
    expect(PartyStatement.monthsOf(books, 'p1'), ['2026-09', '2026-08']);
    expect(PartyStatement.monthsOf(books, 'p2'), ['2026-09']);
    expect(PartyStatement.monthsOf(books, 'nobody'), isEmpty);
  });

  test('one month: only its trips, totals recomputed from them, none for an empty month', () {
    final s = PartyStatement.of(books, 'p1', month: '2026-09')!;
    expect(s.trips.map((t) => t.bookingId), ['B2', 'B3']);
    expect((s.party.trips, s.party.revenuePaise, s.party.receivedPaise, s.party.duePaise), (2, 5000000, 500000, 4500000));
    expect(s.toCsv().trim().split('\n').last, 'Total,50000.00,5000.00,45000.00');
    expect(PartyStatement.of(books, 'p1', month: '2026-07'), isNull);
    // the whole statement is unchanged
    final all = PartyStatement.of(books, 'p1')!;
    expect(all.trips.length, 4);
    expect(all.month, isNull);
  });

  test('month-by-month CSV: oldest first, exact paise, a total that matches the dated trips', () {
    final lines = PartyStatement.monthlyCsv(books, 'p1').trim().split('\n');
    expect(lines.first, 'month,trips,revenue_inr,received_inr,due_inr');
    expect(lines[1], '2026-08,1,10000.00,10000.00,0.00');
    expect(lines[2], '2026-09,2,50000.00,5000.00,45000.00');
    expect(lines.last, 'Total,3,60000.00,15000.00,45000.00');
  });

  test('the PDF of one month is produced', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await PartyStatement.of(books, 'p1', month: '2026-09')!.toPdf(company: 'Sharma Roadlines');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  testWidgets('the sheet lets the transporter pick a month and offers the month-by-month file', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: TransporterBooksScreen(accounts: Stream.value(accounts)))));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('partyStatement_p1')));
    await settle(tester);
    expect(find.byKey(const ValueKey('stmtMonthAll')), findsOneWidget);
    expect(find.byKey(const ValueKey('stmtMonth_2026-09')), findsOneWidget);
    expect(find.byKey(const ValueKey('stmtMonth_2026-08')), findsOneWidget);
    expect(find.byKey(const ValueKey('partyMonthlyCsv')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stmtMonth_2026-08')));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('stmtMonth_2026-08'))).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('stmtMonthAll'))).selected, isFalse);
  });
}
