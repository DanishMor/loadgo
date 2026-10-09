import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/payout.dart';
import '../core/services/payout_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin: payout requests. Pay outside the app, then mark the request paid
/// (or reject it). Nothing moves money from here.
class AdminPayoutsScreen extends StatelessWidget {
  const AdminPayoutsScreen({super.key});

  Future<void> _set(BuildContext context, Payout p, String status) async {
    try {
      await PayoutService.setStatus(p.id, status);
      if (context.mounted) showSnack(context, tr(context, 'statusUpdated'));
    } catch (error) {
      if (context.mounted) showSnack(context, errorText(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminPayouts'))),
      body: LiveStream<List<Payout>>(
        stream: PayoutService.watchAll,
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.account_balance_outlined, title: tr(context, 'adminNothingHere'));
          return ListView.builder(padding: const EdgeInsets.all(16), itemCount: list.length, itemBuilder: (context, i) {
            final p = list[i];
            return ListTile(
                key: ValueKey('adminPayout_${p.id}'),
                title: Text('${formatPaise(p.amountPaise)} · ${p.driverId}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${tr(context, 'payout_${p.status}')}${p.createdAt == null ? '' : ' · ${formatDateTime(p.createdAt!)}'}'),
                trailing: p.status == Payout.requested
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(key: ValueKey('rejectPayout_${p.id}'), onPressed: () => _set(context, p, Payout.rejected), child: Text(tr(context, 'reject'))),
                        FilledButton(key: ValueKey('paidPayout_${p.id}'), onPressed: () => _set(context, p, Payout.paid), child: Text(tr(context, 'markClaimPaid'))),
                      ])
                    : null,
            );
          });
        },
      ),
    );
  }
}
