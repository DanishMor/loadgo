import '../core/security/secure_screen.dart';
import 'driver_trip_screen.dart';
import '../core/payments/wallet_widgets.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/ledger_entry.dart';
import '../core/models/payout.dart';
import '../core/services/booking_service.dart';
import '../core/services/payment_service.dart';
import '../core/services/payout_service.dart';
import '../core/payments/statement_sheet.dart';
import '../core/wallet/payout_flow.dart';
import '../core/wallet/txn_history_screen.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/theme/design_tokens.dart';

/// Driver wallet: pending / available / paid-out figures, payout requests,
/// and the ledger lines (trip earnings and platform commission). Records
/// only: LoadGo pays requests by hand for now. LATER(paid): bank payouts.
class WalletScreen extends StatefulWidget {
  /// Opens a trip (the waiting card); defaults to the driver trip screen.
  final void Function(BuildContext, String bookingId)? onOpenTrip;
  const WalletScreen({super.key, this.onOpenTrip});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late final Stream<List<LedgerEntry>> _ledger = PaymentService.watchLedger().asBroadcastStream();
  late final Stream<List<Booking>> _bookings = BookingService.watchForDriver().asBroadcastStream();
  late final Stream<List<Payout>> _payouts = PayoutService.watchMine().asBroadcastStream();

  Widget _total(String label, int paise, {Color? color, Key? key}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: DsStyle.t12w400.copyWith(color: AppColors.muted)),
            Text(formatPaise(paise), key: key, style: DsStyle.t16w700.copyWith(color: color ?? AppColors.title)),
          ],
        ),
      );

  Future<void> _requestPayout(WalletBalances b) => startPayoutRequest(context, b);

  Color _statusColor(String s) => switch (s) {
        Payout.paid => AppColors.success,
        Payout.rejected => Colors.redAccent,
        _ => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    return SecureScope(child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'wallet'), style: DsStyle.w700),
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
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        key: const ValueKey('openStatement'),
                        onPressed: () => showStatementSheet(context, entries: entries, bookings: bookings),
                        icon: const Icon(Icons.download_outlined),
                        label: Text(tr(context, 'stmtTitle')),
                      ),
                    ),
                    Text(tr(context, 'recordsOnly'), style: DsStyle.t12w400.copyWith(color: AppColors.faint)),
                    if (payouts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(tr(context, 'payoutHistory'), style: DsStyle.t18w700),
                      for (final p in payouts)
                        ListTile(
                          key: ValueKey('payout_${p.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.account_balance_outlined),
                          title: Text(formatPaise(p.amountPaise), style: DsStyle.w700),
                          subtitle: p.createdAt == null ? null : Text(formatDateTime(p.createdAt!)),
                          trailing: StatusChip(label: tr(context, 'payout_${p.status}'), color: _statusColor(p.status)),
                        ),
                    ],
                    WalletWaitingCard(bookings: bookings, onOpen: widget.onOpenTrip ?? (c, id) => openDriverTrip(c, id)),
                    const SizedBox(height: 12),
                    if (entries.isEmpty) Text(tr(context, 'noLedger'), style: DsStyle.inherit.copyWith(color: AppColors.muted)),
                    for (final e in entries)
                      ListTile(
                        key: ValueKey('ledger_${e.id}'),
                        onTap: () => showLedgerLine(context, e, entries),
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
                        trailing: Text(formatPaise(e.amountPaise), style: DsStyle.w700),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ));
  }
}
