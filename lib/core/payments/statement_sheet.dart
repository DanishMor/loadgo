import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/ledger_entry.dart';
import '../services/server_clock.dart';
import '../share/share_csv.dart';
import '../widgets/common.dart';
import 'earnings_statement.dart';

/// Bottom sheet on the wallet: pick a period, share the earnings as CSV or PDF.
Future<void> showStatementSheet(BuildContext context, {required List<LedgerEntry> entries, required List<Booking> bookings, String driverName = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => StatementSheet(entries: entries, bookings: bookings, driverName: driverName),
  );
}

class StatementSheet extends StatefulWidget {
  final List<LedgerEntry> entries;
  final List<Booking> bookings;
  final String driverName;
  /// For tests; the server's "now" otherwise.
  final DateTime Function()? now;

  const StatementSheet({super.key, required this.entries, required this.bookings, this.driverName = '', this.now});

  @override
  State<StatementSheet> createState() => _StatementSheetState();
}

class _StatementSheetState extends State<StatementSheet> {
  StatementPeriod _period = StatementPeriod.thisMonth;
  bool _busy = false;

  EarningsStatement get _statement {
    final (from, to) = _period.range((widget.now ?? ServerClock.now)());
    return EarningsStatement.build(widget.entries, widget.bookings, from: from, to: to);
  }

  static const _labels = {
    StatementPeriod.thisMonth: 'stmtMonth',
    StatementPeriod.lastMonth: 'stmtLastMonth',
    StatementPeriod.financialYear: 'stmtFy',
    StatementPeriod.all: 'stmtAll',
  };

  Future<void> _share(bool pdf) async {
    final s = _statement;
    if (s.rows.isEmpty) return showSnack(context, tr(context, 'stmtEmpty'));
    setState(() => _busy = true);
    try {
      if (pdf) {
        await Printing.sharePdf(bytes: await s.toPdf(driverName: widget.driverName), filename: 'earnings-statement.pdf');
      } else {
        await shareCsv(s.toCsv(), 'Earnings statement');
      }
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _statement;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(tr(context, 'stmtTitle'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final p in StatementPeriod.values)
              ChoiceChip(
                key: ValueKey('stmtPeriod_${p.name}'),
                label: Text(tr(context, _labels[p]!)),
                selected: _period == p,
                onSelected: (_) => setState(() => _period = p),
              ),
          ]),
          const SizedBox(height: 12),
          Text('${s.rows.length} · ${formatPaise(s.earningPaise)} − ${formatPaise(-s.commissionPaise)} = ${formatPaise(s.netPaise)}', key: const ValueKey('stmtTotals'), style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          FilledButton.icon(key: const ValueKey('stmtCsv'), onPressed: _busy ? null : () => _share(false), icon: const Icon(Icons.table_chart_outlined), label: Text(tr(context, 'stmtCsv'))),
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const ValueKey('stmtPdf'), onPressed: _busy ? null : () => _share(true), icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(tr(context, 'stmtPdf'))),
        ]),
      ),
    );
  }
}
