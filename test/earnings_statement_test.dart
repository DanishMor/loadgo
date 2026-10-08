import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/payments/earnings_statement.dart';
import 'package:transport_app/core/payments/statement_sheet.dart';

Booking _b(String id, String pickup, String drop) => Booking(
      id: id, loadId: 'L$id', driverId: 'd1', vehicleId: 'v', customerId: 'c', status: BookingStatus.delivered, pickup: pickup, drop: drop, cargoType: 'x', weight: 1,
      vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1234', driverName: 'D', driverPhone: '', timeline: const {},
    );

LedgerEntry _e(String booking, String type, int paise, DateTime at) =>
    LedgerEntry(id: '${booking}_$type', driverId: 'd1', bookingId: booking, type: type, amountPaise: paise, createdAt: at);

void main() {
  final entries = [
    _e('B1', LedgerType.tripEarning, 2400000, DateTime(2026, 9, 10)),
    _e('B1', LedgerType.platformCommission, -120000, DateTime(2026, 9, 10)),
    _e('B2', LedgerType.tripEarning, 1500050, DateTime(2026, 10, 3)),
    _e('B2', LedgerType.platformCommission, -75003, DateTime(2026, 10, 3)),
    _e('B3', LedgerType.tripEarning, 900000, DateTime(2026, 3, 30)),
  ];
  final bookings = [_b('B1', 'Pune', 'Delhi'), _b('B2', 'Mumbai, MH', 'Surat'), _b('B3', 'Agra', 'Jaipur')];
  final now = DateTime(2026, 10, 8);

  test('periods: this month, last month, the Indian financial year, all', () {
    expect(StatementPeriod.thisMonth.range(now), (DateTime(2026, 10, 1), DateTime(2026, 10, 31)));
    expect(StatementPeriod.lastMonth.range(now), (DateTime(2026, 9, 1), DateTime(2026, 9, 30)));
    expect(StatementPeriod.financialYear.range(now), (DateTime(2026, 4, 1), DateTime(2027, 3, 31)));
    expect(StatementPeriod.financialYear.range(DateTime(2027, 2, 1)), (DateTime(2026, 4, 1), DateTime(2027, 3, 31)));
    expect(StatementPeriod.all.range(now), (null, null));
    expect(StatementPeriod.lastMonth.range(DateTime(2026, 1, 15)), (DateTime(2025, 12, 1), DateTime(2025, 12, 31)));
  });

  test('rows are the trips inside the period with exact paise totals', () {
    final (from, to) = StatementPeriod.financialYear.range(now);
    final s = EarningsStatement.build(entries, bookings, from: from, to: to);
    expect(s.rows.map((r) => r.bookingId), ['B1', 'B2']);
    expect(s.earningPaise, 2400000 + 1500050);
    expect(s.commissionPaise, -120000 - 75003);
    expect(s.netPaise, s.earningPaise + s.commissionPaise);
    expect(EarningsStatement.build(entries, bookings).rows, hasLength(3));
    expect(EarningsStatement.build(entries, bookings, from: DateTime(2025, 1, 1), to: DateTime(2025, 1, 31)).rows, isEmpty);
  });

  test('a ledger line on the last day is inside; one second after midnight is not', () {
    final s = EarningsStatement.build([_e('B1', LedgerType.tripEarning, 100, DateTime(2026, 9, 30, 23, 59, 59))], bookings, from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    expect(s.rows, hasLength(1));
    final t = EarningsStatement.build([_e('B1', LedgerType.tripEarning, 100, DateTime(2026, 10, 1, 0, 0, 1))], bookings, from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    expect(t.rows, isEmpty);
  });

  test('rupees come from integer paise with two decimals and a sign', () {
    expect(EarningsStatement.rupees(0), '0.00');
    expect(EarningsStatement.rupees(5), '0.05');
    expect(EarningsStatement.rupees(1500050), '15000.50');
    expect(EarningsStatement.rupees(-75003), '-750.03');
  });

  test('the CSV has a header, one row per trip with quoted commas, and a total row', () {
    final s = EarningsStatement.build(entries, bookings, from: DateTime(2026, 4, 1), to: DateTime(2027, 3, 31));
    final lines = s.toCsv().trim().split('\n');
    expect(lines.first, EarningsStatement.csvHeader);
    expect(lines, hasLength(4));
    expect(lines[2], '2026-10-03,B2,"Mumbai, MH - Surat",15000.50,-750.03,14250.47');
    expect(lines.last, ',,Total,39000.50,-1950.03,37050.47');
  });

  test('the PDF is produced', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await EarningsStatement.build(entries, bookings).toPdf(driverName: 'Ramesh');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  testWidgets('the sheet shows the totals of the chosen period', (tester) async {
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: StatementSheet(entries: entries, bookings: bookings, now: () => now))),
    ));
    expect(find.textContaining('1 ·'), findsOneWidget); // October: one trip
    await tester.tap(find.byKey(const ValueKey('stmtPeriod_all')));
    await tester.pump();
    expect(find.textContaining('3 ·'), findsOneWidget);
  });
}
