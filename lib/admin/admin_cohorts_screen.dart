import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/admin/pilot_cohorts.dart';
import '../core/l10n/l10n.dart';
import '../core/constants/cancel_reasons.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Pilot cohorts (MASTER-6 Task 6): per week of posting, time to the
/// first bid and to a driver, customers who came back, cancel reasons; CSV.
class AdminCohortsScreen extends StatefulWidget {
  /// Test hook; defaults to the live reads.
  final Future<List<CohortRow>> Function()? load;
  const AdminCohortsScreen({super.key, this.load});

  @override
  State<AdminCohortsScreen> createState() => _AdminCohortsScreenState();
}

class _AdminCohortsScreenState extends State<AdminCohortsScreen> {
  late Future<List<CohortRow>> _data = (widget.load ?? AdminConsoleService.pilotCohorts)();

  void _refresh() {
    final next = (widget.load ?? AdminConsoleService.pilotCohorts)();
    setState(() {
      _data = next;
    });
  }

  String _time(int? m) {
    if (m == null) return tr(context, 'pcohNever');
    return m < 120 ? trf(context, 'pcohMin', {'n': m}) : trf(context, 'pcohHours', {'h': m ~/ 60, 'm': m % 60});
  }

  String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _card(CohortRow r) {
    final reasons = r.cancelReasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return AppCard(
      key: ValueKey('cohort_${_date(r.week)}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(trf(context, 'pcohWeek', {'date': _date(r.week)}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text(trf(context, 'pcohLoads', {'n': r.loads})),
        Text(trf(context, 'pcohFirstBid', {'t': _time(r.medianFirstBidMinutes), 'n': r.withBid})),
        Text(trf(context, 'pcohFill', {'t': _time(r.medianFillMinutes), 'n': r.filled})),
        Text(trf(context, 'pcohRepeat', {'r': r.repeatCustomers, 'c': r.customers})),
        if (reasons.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(tr(context, 'pcohCancels'), style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final e in reasons) Text('${e.key == PilotCohorts.noReason ? tr(context, 'pcohNoReason') : tr(context, CancelReasons.labelKey(e.key))}: ${e.value}'),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminCohorts')), actions: [IconButton(key: const ValueKey('cohRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<CohortRow>>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final rows = snap.data;
          if (rows == null) return const Center(child: CircularProgressIndicator());
          if (rows.isEmpty) return EmptyState(icon: Icons.query_stats_rounded, title: tr(context, 'pcohNone'));
          return ListView(padding: const EdgeInsets.all(16), children: [
            FilledButton.icon(
              key: const ValueKey('cohCsv'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: PilotCohorts.toCsv(rows)));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'copied'))));
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(tr(context, 'pcohCsv')),
            ),
            const SizedBox(height: 8),
            for (final r in rows) ...[_card(r), const SizedBox(height: 8)],
            Text(tr(context, 'pcohFootnote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ]);
        },
      ),
    );
  }
}
