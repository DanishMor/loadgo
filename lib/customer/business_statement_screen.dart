import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/business.dart';
import '../core/services/business_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Monthly record of the company's delivered trips, split by cost centre.
/// The owner can save it (a record, not an invoice) or copy it as CSV.
class BusinessStatementScreen extends StatefulWidget {
  final Stream<List<Booking>>? bookings;
  final DateTime Function() now;

  const BusinessStatementScreen({super.key, this.bookings, this.now = DateTime.now});

  @override
  State<BusinessStatementScreen> createState() => _BusinessStatementScreenState();
}

class _BusinessStatementScreenState extends State<BusinessStatementScreen> {
  late final Stream<List<Booking>> _bookings = (widget.bookings ?? BusinessService.watchCompanyBookings()).asBroadcastStream();
  late DateTime _month = DateTime(widget.now().year, widget.now().month);

  void _shift(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  Future<void> _save(MonthlyStatement s) async {
    try {
      await BusinessService.saveStatement(s);
      if (mounted) showSnack(context, tr(context, 'statementSaved'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'monthlyStatement'))),
      body: LiveStream<List<Booking>>(
        stream: () => _bookings,
        builder: (context, bookings) {
          final s = MonthlyStatement.from(bookings, _month);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(key: const ValueKey('stmtPrev'), onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
              Text(s.month, key: const ValueKey('stmtMonth'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              IconButton(key: const ValueKey('stmtNext'), onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
            ]),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'statementTotal'), style: const TextStyle(color: AppColors.muted)),
                Text(formatPaise(s.totalPaise), key: const ValueKey('stmtTotal'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                Text(trf(context, 'fleetTripsDone', {'n': s.trips}), style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
            const SizedBox(height: 12),
            Text(tr(context, 'byCostCenter'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            if (s.trips == 0) Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'statementEmpty'))),
            for (final e in s.sortedCenters)
              ListTile(
                key: ValueKey('center_${e.key}'),
                contentPadding: EdgeInsets.zero,
                title: Text(e.key.isEmpty ? tr(context, 'noCostCenter') : e.key),
                trailing: Text(formatPaise(e.value), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            const SizedBox(height: 8),
            Text(tr(context, 'statementNote'), style: const TextStyle(color: AppColors.faint, fontSize: 12)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('stmtCsv'),
                  onPressed: s.trips == 0
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: s.toCsv()));
                          if (context.mounted) showSnack(context, tr(context, 'csvCopied'));
                        },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(tr(context, 'copyCsv')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('stmtSave'),
                  onPressed: s.trips == 0 ? null : () => _save(s),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tr(context, 'saveStatement')),
                ),
              ),
            ]),
          ]);
        },
      ),
    );
  }
}
