import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/ledger_entry.dart';
import '../models/support_ticket.dart';
import '../support/support_screens.dart';
import '../widgets/common.dart';
import 'payment_timeline.dart';
import 'wallet_insight.dart';

/// "Money on its way": the delivered trips whose payment is not confirmed, who
/// has to move next, and the steps in one line (MASTER-6 Task 25).
class WalletWaitingCard extends StatelessWidget {
  final List<Booking> bookings;

  /// Opens a trip; when null the card is not tappable.
  final void Function(BuildContext, String bookingId)? onOpen;
  const WalletWaitingCard({super.key, required this.bookings, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final w = WalletInsight.waiting(bookings);
    if (w.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        key: const ValueKey('walletWaiting'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trf(context, 'wlWaitTitle', {'amount': formatPaise(WalletInsight.waitingTotal(w))}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          for (final t in w.take(5))
            InkWell(
              key: ValueKey('waiting_${t.booking.id}'),
              onTap: onOpen == null ? null : () => onOpen!(context, t.booking.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(t.next == PaymentNext.confirmReceived ? Icons.touch_app_rounded : Icons.hourglass_empty_rounded, size: 20, color: t.next == PaymentNext.confirmReceived ? AppColors.warning : AppColors.faint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${t.booking.pickup} → ${t.booking.drop}${t.amountPaise > 0 ? ' · ${formatPaise(t.amountPaise)}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(tr(context, t.next == PaymentNext.confirmReceived ? 'wlWaitYou' : 'wlWaitCustomer'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 6),
          Text(tr(context, 'wlWaitSteps'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
        ]),
      ),
    );
  }
}

String ledgerKindKey(LedgerEntry e) => e.type == LedgerType.tripEarning ? 'walletEarnings' : 'walletCommission';

/// What a wallet line is, in a sentence, and a way to question it (a support
/// ticket about this trip with the line already described).
Future<void> showLedgerLine(BuildContext context, LedgerEntry e, Iterable<LedgerEntry> all) {
  final percent = WalletInsight.commissionPercent(all, e.bookingId);
  final trip = 'LG-${e.bookingId.length > 10 ? e.bookingId.substring(0, 10).toUpperCase() : e.bookingId.toUpperCase()}';
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.card,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${tr(c, ledgerKindKey(e))} · ${formatPaise(e.amountPaise)}', key: const ValueKey('ledgerSheetTitle'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text([trip, if (e.createdAt != null) formatDateTime(e.createdAt!)].join(' • '), style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          Text(
            e.type == LedgerType.tripEarning
                ? tr(c, 'wlWhyEarning')
                : '${tr(c, 'wlWhyCommission')}${percent == null ? '' : ' ${trf(c, 'wlShare', {'p': percent})}'}',
            key: const ValueKey('ledgerWhy'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const ValueKey('ledgerQuestion'),
            icon: const Icon(Icons.help_outline_rounded),
            label: Text(tr(c, 'wlQuestion')),
            onPressed: () {
              Navigator.pop(c);
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => NewTicketScreen(
                  bookingId: e.bookingId,
                  category: TicketCategory.payment,
                  initialSubject: trf(context, 'wlQuestionSubject', {'kind': tr(context, ledgerKindKey(e)), 'trip': trip}),
                  initialDescription: trf(context, 'wlQuestionBody', {'amount': formatPaise(e.amountPaise), 'date': e.createdAt == null ? '' : formatDateTime(e.createdAt!)}),
                ),
              ));
            },
          ),
        ]),
      ),
    ),
  );
}
