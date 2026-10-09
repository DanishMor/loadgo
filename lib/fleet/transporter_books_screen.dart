import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/services/transporter_service.dart';
import '../core/share/share_csv.dart';
import '../core/transporter/party_statement.dart';
import '../core/transporter/transporter_logic.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Opens the books line of one trip: what the party pays, what the driver is
/// owed, other cost and what has come in. A record for the transporter's own
/// accounts, integer paise, no money moves.
Future<void> editTripAccount(BuildContext context, Booking booking, {TripAccount? existing}) async {
  String rupees(int? p) => p == null || p == 0 ? '' : (p % 100 == 0 ? '${p ~/ 100}' : (p / 100).toStringAsFixed(2));
  final party = TextEditingController(text: existing?.partyName ?? '');
  final revenue = TextEditingController(text: rupees(existing?.revenuePaise ?? booking.billAmountPaise));
  final driver = TextEditingController(text: rupees(existing?.driverPayPaise));
  final other = TextEditingController(text: rupees(existing?.otherCostPaise));
  final received = TextEditingController(text: rupees(existing?.receivedPaise));
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(c, 'trpBooks')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(c, 'trpBooksNote'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(key: const ValueKey('acctParty'), controller: party, decoration: InputDecoration(labelText: tr(c, 'company')), inputFormatters: [LengthLimitingTextInputFormatter(80)]),
          for (final e in [
            ('acctRevenue', revenue, 'trpRevenue'),
            ('acctDriver', driver, 'trpDriverPay'),
            ('acctOther', other, 'trpOtherCost'),
            ('acctReceived', received, 'trpReceived'),
          ])
            TextField(
              key: ValueKey(e.$1),
              controller: e.$2,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr(c, e.$3)),
              inputFormatters: [LengthLimitingTextInputFormatter(12)],
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
        FilledButton(key: const ValueKey('acctSave'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'save'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final values = [for (final c in [revenue, driver, other, received]) TripAccount.paiseFromRupees(c.text)];
  if (values.any((v) => v == null)) return showSnack(context, tr(context, 'trpBadAmount'));
  try {
    await TransporterService.saveAccount(
      booking: booking,
      partyName: party.text,
      revenuePaise: values[0]!,
      driverPayPaise: values[1]!,
      otherCostPaise: values[2]!,
      receivedPaise: values[3]!,
    );
    if (context.mounted) showSnack(context, tr(context, 'trpSaved'));
  } catch (error) {
    if (context.mounted) showSnack(context, errorText(context, error));
  }
}

/// Totals (margin, owed to drivers, due from parties) and the party-wise
/// balance, largest due first.
class TransporterBooksScreen extends StatelessWidget {
  /// Injectable for tests.
  final Stream<List<TripAccount>>? accounts;

  const TransporterBooksScreen({super.key, this.accounts});

  Widget _row(String label, String value, {Key? key, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, key: key, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'trpBooks'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: LiveStream<List<TripAccount>>(
          stream: () => accounts ?? TransporterService.watchBooks(),
          builder: (context, list) {
            if (list.isEmpty) return EmptyState(icon: Icons.account_balance_wallet_outlined, title: tr(context, 'trpNoBooks'));
            final books = TransporterBooks.from(list);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 30), children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: const ValueKey('booksExportAll'),
                  onPressed: () => shareCsv(PartyStatement.allPartiesCsv(books), 'Parties'),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: Text(tr(context, 'trpExportParties')),
                ),
              ),
              AppCard(
                child: Column(children: [
                  _row(tr(context, 'trpTotalMargin'), formatPaise(books.marginPaise), key: const ValueKey('booksMargin'), color: books.marginPaise < 0 ? Colors.red : AppColors.success),
                  _row(tr(context, 'trpTotalDriverPay'), formatPaise(books.driverPayPaise), key: const ValueKey('booksDriverPay')),
                  _row(tr(context, 'trpTotalDue'), formatPaise(books.dueFromPartiesPaise), key: const ValueKey('booksDue')),
                ]),
              ),
              const SizedBox(height: 8),
              Text(tr(context, 'trpBooksNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
              const SizedBox(height: 14),
              Text(tr(context, 'trpPartyDues'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final p in books.parties)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    key: ValueKey('party_${p.partyId}'),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.partyName.isEmpty ? p.partyId : p.partyName, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(trf(context, 'trpTripsCount', {'n': p.trips}), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                      ),
                      Text(formatPaise(p.duePaise), key: ValueKey('partyDue_${p.partyId}'), style: TextStyle(fontWeight: FontWeight.w800, color: p.duePaise > 0 ? AppColors.warning : AppColors.success)),
                      IconButton(
                        key: ValueKey('partyStatement_${p.partyId}'),
                        tooltip: tr(context, 'trpPartyStatement'),
                        icon: const Icon(Icons.ios_share_rounded),
                        onPressed: () => showPartyStatementSheet(context, PartyStatement.of(books, p.partyId)!, books: books),
                      ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

/// Share one party's statement as CSV or PDF. With [books] the statement can
/// be cut to one month, and a month-by-month CSV is offered (MASTER-6 Task 30).
Future<void> showPartyStatementSheet(BuildContext context, PartyStatement statement, {TransporterBooks? books}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => _PartyStatementSheet(statement: statement, books: books),
  );
}

class _PartyStatementSheet extends StatefulWidget {
  final PartyStatement statement;
  final TransporterBooks? books;
  const _PartyStatementSheet({required this.statement, this.books});

  @override
  State<_PartyStatementSheet> createState() => _PartyStatementSheetState();
}

class _PartyStatementSheetState extends State<_PartyStatementSheet> {
  String? _month;

  PartyStatement get _shown => _month == null || widget.books == null ? widget.statement : (PartyStatement.of(widget.books!, widget.statement.party.partyId, month: _month) ?? widget.statement);

  @override
  Widget build(BuildContext context) {
    final c = context;
    final st = _shown;
    final months = widget.books == null ? const <String>[] : PartyStatement.monthsOf(widget.books!, widget.statement.party.partyId);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trf(c, 'trpPartyStatementFor', {'party': st.party.partyName.isEmpty ? st.party.partyId : st.party.partyName}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (months.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              ChoiceChip(key: const ValueKey('stmtMonthAll'), label: Text(tr(c, 'stmtAllMonths')), selected: _month == null, onSelected: (_) => setState(() => _month = null)),
              for (final m in months.take(12)) ChoiceChip(key: ValueKey('stmtMonth_$m'), label: Text(m), selected: _month == m, onSelected: (_) => setState(() => _month = m)),
            ]),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(key: const ValueKey('partyCsv'), onPressed: () => shareCsv(st.toCsv(), 'Statement'), icon: const Icon(Icons.table_chart_outlined), label: Text(tr(c, 'stmtCsv'))),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('partyPdf'),
            onPressed: () async => Printing.sharePdf(bytes: await st.toPdf(), filename: 'statement${st.month == null ? '' : '-${st.month}'}.pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(tr(c, 'stmtPdf')),
          ),
          if (months.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('partyMonthlyCsv'),
              onPressed: () => shareCsv(PartyStatement.monthlyCsv(widget.books!, widget.statement.party.partyId), 'Statement by month'),
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(tr(c, 'stmtMonthlyCsv')),
            ),
          ],
        ]),
      ),
    );
  }
}
