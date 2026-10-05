import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/ledger_entry.dart';
import '../core/models/payout.dart';
import '../core/services/booking_service.dart';
import '../core/services/payment_service.dart';
import '../core/services/payout_service.dart';
import '../core/models/risk.dart';
import '../core/wallet/txn_history_screen.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Driver wallet: pending / available / paid-out figures, payout requests,
/// and the ledger lines (trip earnings and platform commission). Records
/// only: LoadGo pays requests by hand for now. LATER(paid): bank payouts.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late final Stream<List<LedgerEntry>> _ledger = PaymentService.watchLedger().asBroadcastStream();
  late final Stream<List<Booking>> _bookings = BookingService.watchForDriver().asBroadcastStream();
  late final Stream<List<Payout>> _payouts = PayoutService.watchMine().asBroadcastStream();

  Widget _total(String label, int paise, {Color color = AppColors.title, Key? key}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(formatPaise(paise), key: key, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          ],
        ),
      );

  Future<void> _requestPayout(WalletBalances b) async {
    final ctrl = TextEditingController(text: (b.available / 100).toStringAsFixed(b.available % 100 == 0 ? 0 : 2));
    final rupees = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'requestPayout')),
        content: TextField(
          key: const ValueKey('payoutAmount'),
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(prefixIcon: const Icon(Icons.currency_rupee_rounded), helperText: trf(context, 'payoutAvailable', {'amount': formatPaise(b.available)})),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
          FilledButton(
            key: const ValueKey('payoutSubmit'),
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text.trim())),
            child: Text(tr(context, 'requestPayout')),
          ),
        ],
      ),
    );
    // The dialog is still animating out, so the controller is not disposed here.
    if (rupees == null || !mounted) return;
    try {
      await PayoutService.request((rupees * 100).round());
      if (mounted) showSnack(context, tr(context, 'payoutRequested'));
    } on PayoutException catch (e) {
      if (mounted) {
        showSnack(context, tr(context, switch (e.reason) {
          'too_much' => 'payoutTooMuch',
          'open_request' => 'payoutOpenRequest',
          _ => 'payoutAmountInvalid',
        }));
      }
    } on AccountRestrictedException {
      if (mounted) showSnack(context, tr(context, 'accountRestricted'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Color _statusColor(String s) => switch (s) {
        Payout.paid => AppColors.success,
        Payout.rejected => Colors.redAccent,
        _ => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'wallet'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            key: const ValueKey('openTxnHistory'),
            tooltip: tr(context, 'txnTitle'),
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TxnHistoryScreen(isDriver: true))),
          ),
        ],
      ),
      body: SafeArea(
        child: LiveStream<List<LedgerEntry>>(
          stream: () => _ledger,
          builder: (context, entries) => LiveStream<List<Booking>>(
            stream: () => _bookings,
            compact: true,
            builder: (context, bookings) => LiveStream<List<Payout>>(
              stream: () => _payouts,
              compact: true,
              builder: (context, payouts) {
                final sum = WalletSummary.of(entries);
                final bal = WalletBalances.of(ledger: entries, bookings: bookings, payouts: payouts);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                  children: [
                    AppCard(
                      child: Column(children: [
                        Row(children: [
                          _total(tr(context, 'walletPending'), bal.pending, color: AppColors.warning, key: const ValueKey('walletPending')),
                          _total(tr(context, 'walletAvailable'), bal.available, color: AppColors.success, key: const ValueKey('walletAvailable')),
                          _total(tr(context, 'walletPaidOut'), bal.paidOut, key: const ValueKey('walletPaidOut')),
                        ]),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const ValueKey('requestPayout'),
                            onPressed: bal.available >= Payout.minPaise && bal.requested == 0 ? () => _requestPayout(bal) : null,
                            icon: const Icon(Icons.account_balance_outlined),
                            label: Text(bal.requested > 0
                                ? trf(context, 'payoutWaiting', {'amount': formatPaise(bal.requested)})
                                : tr(context, 'requestPayout')),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
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
                    if (payouts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(tr(context, 'payoutHistory'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      for (final p in payouts)
                        ListTile(
                          key: ValueKey('payout_${p.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.account_balance_outlined),
                          title: Text(formatPaise(p.amountPaise), style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: p.createdAt == null ? null : Text(formatDateTime(p.createdAt!)),
                          trailing: StatusChip(label: tr(context, 'payout_${p.status}'), color: _statusColor(p.status)),
                        ),
                    ],
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
        ),
      ),
    );
  }
}
