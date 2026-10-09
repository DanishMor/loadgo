import 'package:flutter/material.dart';

import '../core/admin/payment_aging.dart';
import '../core/errors/friendly_error.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Payment aging (MASTER-6 Task 8): delivered trips whose payment
/// record is not done, by age, with a Remind button (one per 6 hours).
class AdminPaymentAgingScreen extends StatefulWidget {
  /// Test hooks; default to the live read and write.
  final Future<List<AgingRow>> Function()? load;
  final Future<void> Function(AgingRow)? nudge;
  const AdminPaymentAgingScreen({super.key, this.load, this.nudge});

  @override
  State<AdminPaymentAgingScreen> createState() => _AdminPaymentAgingScreenState();
}

class _AdminPaymentAgingScreenState extends State<AdminPaymentAgingScreen> {
  late Future<List<AgingRow>> _data = (widget.load ?? AdminConsoleService.paymentAging)();
  final _sent = <String>{};

  void _refresh() {
    final next = (widget.load ?? AdminConsoleService.paymentAging)();
    setState(() {
      _data = next;
    });
  }

  Future<void> _remind(AgingRow r) async {
    try {
      await (widget.nudge ?? AdminConsoleService.nudgePayment)(r);
      if (!mounted) return;
      setState(() => _sent.add(PaymentAging.nudgeId(r.bookingId, r.waitingOn)));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'pagNudged'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, FriendlyError.of(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminPayAging')), actions: [IconButton(key: const ValueKey('pagRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<AgingRow>>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final rows = snap.data;
          if (rows == null) return const Center(child: CircularProgressIndicator());
          if (rows.isEmpty) return EmptyState(icon: Icons.task_alt_rounded, title: tr(context, 'pagNone'));
          final counts = PaymentAging.countByBucket(rows);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in PaymentAging.buckets) Chip(key: ValueKey('pagCount_$b'), label: Text('${tr(context, 'pagBucket_$b')}: ${counts[b]}')),
            ]),
            const SizedBox(height: 8),
            for (final r in rows)
              AppCard(
                key: ValueKey('pag_${r.bookingId}_${r.waitingOn}'),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r.bookingId} · ${trf(context, 'pagDays', {'n': r.ageDays})}${r.amountPaise > 0 ? ' · ${formatPaise(r.amountPaise)}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(tr(context, r.waitingOn == 'driver' ? 'pagWaitDriver' : 'pagWaitCustomer'), style: TextStyle(color: AppColors.muted)),
                    ]),
                  ),
                  OutlinedButton(
                    key: ValueKey('pagRemind_${r.bookingId}_${r.waitingOn}'),
                    onPressed: _sent.contains(PaymentAging.nudgeId(r.bookingId, r.waitingOn)) ? null : () => _remind(r),
                    child: Text(tr(context, 'pagNudge')),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            Text(tr(context, 'pagFootnote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ]);
        },
      ),
    );
  }
}
