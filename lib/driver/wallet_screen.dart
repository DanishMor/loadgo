import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/ledger_entry.dart';
import '../core/services/payment_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Driver ledger: trip earnings and platform commission lines (records only).
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  Widget _total(String label, int paise, {Color color = AppColors.title}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(formatPaise(paise), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'wallet'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: LiveStream<List<LedgerEntry>>(
          stream: PaymentService.watchLedger,
          builder: (context, entries) {
            final sum = WalletSummary.of(entries);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      _total(tr(context, 'walletEarnings'), sum.earnings),
                      _total(tr(context, 'walletCommission'), sum.commission, color: Colors.redAccent),
                      _total(tr(context, 'walletNet'), sum.net, color: AppColors.success),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(tr(context, 'recordsOnly'), style: const TextStyle(fontSize: 12, color: AppColors.faint)),
                const SizedBox(height: 12),
                if (entries.isEmpty) Text(tr(context, 'noLedger'), style: const TextStyle(color: AppColors.muted)),
                for (final e in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      e.amountPaise >= 0 ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      color: e.amountPaise >= 0 ? AppColors.success : Colors.redAccent,
                    ),
                    title: Text(tr(context, e.type == LedgerType.tripEarning ? 'walletEarnings' : 'walletCommission')),
                    subtitle: Text([
                      'LG-${e.bookingId.length > 10 ? e.bookingId.substring(0, 10).toUpperCase() : e.bookingId.toUpperCase()}',
                      if (e.createdAt != null) formatDateTime(e.createdAt!),
                    ].join(' • ')),
                    trailing: Text(formatPaise(e.amountPaise), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
