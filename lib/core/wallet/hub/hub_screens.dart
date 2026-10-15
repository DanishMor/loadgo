import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../constants/logistics.dart';
import '../../models/booking.dart';
import '../../models/ledger_entry.dart';
import '../../models/payout.dart';
import '../../offers/promo.dart';
import '../../payments/statement_sheet.dart';
import '../../services/booking_service.dart';
import '../../services/payment_service.dart';
import '../../services/payout_service.dart';
import '../../services/rewards_service.dart';
import '../../services/transporter_service.dart';
import '../../theme/design_tokens.dart';
import '../../transporter/transporter_logic.dart';
import '../../widgets/common.dart';
import '../../widgets/ds/app_button.dart';
import '../../widgets/live_stream.dart';
import '../payout_flow.dart';
import 'hub_models.dart';
import 'hub_widgets.dart';

String _day(DateTime? d) => d == null ? '' : formatDateTime(d);

/// Driver: today and this week, pending, available, asked for payout, paid out,
/// the road of the money, payouts and recent lines, a statement (CSV / PDF) and
/// the payout request. Records only; no real money moves through Load 20 yet.
class DriverHubScreen extends StatelessWidget {
  final Stream<List<LedgerEntry>> Function() ledger;
  final Stream<List<Booking>> Function() bookings;
  final Stream<List<Payout>> Function() payouts;
  final DateTime Function() now;

  const DriverHubScreen({
    super.key,
    this.ledger = PaymentService.watchLedger,
    this.bookings = BookingService.watchForDriver,
    this.payouts = PayoutService.watchMine,
    this.now = DateTime.now,
  });

  @override
  Widget build(BuildContext context) {
    return HubFrame(
      role: 'driver',
      builder: (context, v) => LiveStream<List<LedgerEntry>>(
        stream: ledger,
        resubscribeKey: v.round,
        loadingBuilder: (_) => const HubLoading(),
        builder: (context, entries) => LiveStream<List<Booking>>(
          stream: bookings,
          resubscribeKey: v.round,
          compact: true,
          loadingBuilder: (_) => const HubLoading(),
          builder: (context, bks) => LiveStream<List<Payout>>(
            stream: payouts,
            resubscribeKey: v.round,
            compact: true,
            loadingBuilder: (_) => const HubLoading(),
            builder: (context, pays) {
              final hub = DriverHub.from(entries: entries, bookings: bks, payouts: pays, now: now());
              final legacy = WalletBalances.of(ledger: entries, bookings: bks, payouts: pays);
              final canAsk = legacy.available >= Payout.minPaise && legacy.requested == 0;
              return HubList(
                onRefresh: v.refresh,
                children: [
                  HubBalanceCard(
                    valueKey: const ValueKey('hubAvailable'),
                    label: tr(context, 'walletAvailable'),
                    paise: hub.balance.available.paise,
                    hidden: v.hidden,
                  ),
                  const SizedBox(height: DsSpace.s3),
                  HubFigures(figures: [
                    HubFigure(valueKey: const ValueKey('hubToday'), label: tr(context, 'hubToday'), paise: hub.todayPaise, hidden: v.hidden, signed: true),
                    HubFigure(valueKey: const ValueKey('hubWeek'), label: tr(context, 'hubWeek'), paise: hub.weekPaise, hidden: v.hidden, signed: true),
                    HubFigure(valueKey: const ValueKey('hubPending'), label: tr(context, 'walletPending'), paise: hub.pendingPaise, hidden: v.hidden),
                    HubFigure(valueKey: const ValueKey('hubHeld'), label: tr(context, 'hubHeld'), paise: hub.balance.held.paise, hidden: v.hidden),
                    HubFigure(valueKey: const ValueKey('hubPaid'), label: tr(context, 'walletPaidOut'), paise: hub.balance.paidOut.paise, hidden: v.hidden),
                  ]),
                  const SizedBox(height: DsSpace.s3),
                  AppButton(
                    key: const ValueKey('hubRequestPayout'),
                    label: legacy.requested > 0
                        ? trf(context, 'payoutWaiting', {'amount': formatPaise(legacy.requested)})
                        : tr(context, 'requestPayout'),
                    icon: Icons.account_balance_outlined,
                    onPressed: canAsk ? () => startPayoutRequest(context, legacy) : null,
                  ),
                  if (hub.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: DsSpace.s6),
                      child: Text(tr(context, 'hubEmptyDriver'), key: const ValueKey('hubEmpty'), style: DsType.body.copyWith(color: context.ds.textMuted)),
                    )
                  else ...[
                    HubHeading(tr(context, 'hubWhen')),
                    HubStageList(stages: hub.stages, hidden: v.hidden),
                    if (hub.payouts.isNotEmpty) ...[
                      HubHeading(tr(context, 'payoutHistory')),
                      for (final p in hub.payouts.take(20))
                        HubRow(
                          key: ValueKey('hubPayout_${p.id}'),
                          title: tr(context, 'payout_${p.status}'),
                          subtitle: _day(p.createdAt),
                          paise: p.amountPaise,
                          hidden: v.hidden,
                          signed: false,
                        ),
                    ],
                    HubHeading(tr(context, 'hubRecent')),
                    for (final e in hub.entries.take(30))
                      HubRow(
                        key: ValueKey('hubLine_${e.id}'),
                        title: tr(context, e.type == LedgerType.tripEarning ? 'walletEarnings' : (e.type == LedgerType.adjustment ? 'hubAdjustment' : 'walletCommission')),
                        subtitle: [if (e.bookingId.isNotEmpty) 'LG-${e.bookingId.length > 10 ? e.bookingId.substring(0, 10).toUpperCase() : e.bookingId.toUpperCase()}', _day(e.createdAt)].where((x) => x.isNotEmpty).join(' • '),
                        paise: e.amountPaise,
                        hidden: v.hidden,
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppButton(
                        key: const ValueKey('hubStatement'),
                        label: tr(context, 'stmtTitle'),
                        icon: Icons.download_outlined,
                        kind: AppButtonKind.tertiary,
                        expand: false,
                        onPressed: () => showStatementSheet(context, entries: entries, bookings: bks),
                      ),
                    ),
                  ],
                  const HubRecordsOnly(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Customer: credits, what was spent, cancellation charges, credit records.
class CustomerHubScreen extends StatelessWidget {
  final Stream<List<Booking>> Function() bookings;
  final Stream<List<CreditLine>> Function() credits;
  final DateTime Function() now;

  const CustomerHubScreen({
    super.key,
    this.bookings = BookingService.watchForCustomer,
    this.credits = RewardsService.watchCredits,
    this.now = DateTime.now,
  });

  @override
  Widget build(BuildContext context) {
    return HubFrame(
      role: 'customer',
      builder: (context, v) => LiveStream<List<Booking>>(
        stream: bookings,
        resubscribeKey: v.round,
        loadingBuilder: (_) => const HubLoading(),
        builder: (context, bks) => LiveStream<List<CreditLine>>(
          stream: credits,
          resubscribeKey: v.round,
          compact: true,
          loadingBuilder: (_) => const HubLoading(),
          builder: (context, lines) {
            final hub = CustomerHub.from(bookings: bks, credits: lines, now: now());
            return HubList(
              onRefresh: v.refresh,
              children: [
                HubBalanceCard(valueKey: const ValueKey('hubCredits'), label: tr(context, 'hubCredits'), paise: hub.creditsPaise, hidden: v.hidden),
                const SizedBox(height: DsSpace.s3),
                HubFigures(figures: [
                  HubFigure(valueKey: const ValueKey('hubSpentMonth'), label: tr(context, 'hubSpentMonth'), paise: hub.spentMonthPaise, hidden: v.hidden),
                  HubFigure(valueKey: const ValueKey('hubSpentTotal'), label: tr(context, 'hubSpentTotal'), paise: hub.spentTotalPaise, hidden: v.hidden),
                ]),
                if (hub.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: DsSpace.s6),
                    child: Text(tr(context, 'hubEmptyCustomer'), key: const ValueKey('hubEmpty'), style: DsType.body.copyWith(color: context.ds.textMuted)),
                  )
                else ...[
                  if (hub.charges.isNotEmpty) ...[
                    HubHeading(tr(context, 'hubCharges')),
                    for (final (b, charge) in hub.charges.take(20))
                      HubRow(key: ValueKey('hubCharge_${b.id}'), title: '${b.pickup} → ${b.drop}', subtitle: _day(b.timeline[BookingStatus.cancelled]), paise: -charge, hidden: v.hidden),
                  ],
                  if (hub.credits.isNotEmpty) ...[
                    HubHeading(tr(context, 'hubCreditRecords')),
                    for (final c in hub.credits.take(30))
                      HubRow(key: ValueKey('hubCredit_${c.id}'), title: c.note.isNotEmpty ? c.note : c.kind, subtitle: _day(c.createdAt), paise: c.amountPaise, hidden: v.hidden),
                  ],
                ],
                const HubRecordsOnly(),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Transporter: billed, margin, still to come, and a ledger per party.
class TransporterHubScreen extends StatelessWidget {
  final Stream<List<TripAccount>> Function() accounts;

  const TransporterHubScreen({super.key, this.accounts = TransporterService.watchBooks});

  @override
  Widget build(BuildContext context) {
    return HubFrame(
      role: 'transporter',
      builder: (context, v) => LiveStream<List<TripAccount>>(
        stream: accounts,
        resubscribeKey: v.round,
        loadingBuilder: (_) => const HubLoading(),
        builder: (context, list) {
          final hub = TransporterHub.from(list);
          return HubList(
            onRefresh: v.refresh,
            children: [
              HubBalanceCard(valueKey: const ValueKey('hubMargin'), label: tr(context, 'hubMargin'), paise: hub.marginPaise, hidden: v.hidden),
              const SizedBox(height: DsSpace.s3),
              HubFigures(figures: [
                HubFigure(valueKey: const ValueKey('hubRevenue'), label: tr(context, 'hubRevenue'), paise: hub.revenuePaise, hidden: v.hidden),
                HubFigure(valueKey: const ValueKey('hubDue'), label: tr(context, 'hubDue'), paise: hub.dueFromPartiesPaise, hidden: v.hidden),
              ]),
              if (hub.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: DsSpace.s6),
                  child: Text(tr(context, 'hubEmptyTransporter'), key: const ValueKey('hubEmpty'), style: DsType.body.copyWith(color: context.ds.textMuted)),
                )
              else ...[
                HubHeading(tr(context, 'hubParties')),
                for (final p in hub.parties)
                  AppCard(
                    key: ValueKey('hubParty_${p.partyId}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name.isEmpty ? p.partyId : p.name, style: DsType.title.copyWith(color: context.ds.text)),
                      Text(trf(context, 'hubTrips', {'n': p.trips}), style: DsType.caption.copyWith(color: context.ds.textMuted)),
                      const SizedBox(height: DsSpace.s2),
                      Wrap(spacing: DsSpace.s6, runSpacing: DsSpace.s2, children: [
                        HubFigure(label: tr(context, 'hubRevenue'), paise: p.revenuePaise, hidden: v.hidden),
                        HubFigure(label: tr(context, 'hubDue'), paise: p.duePaise, hidden: v.hidden),
                        HubFigure(label: tr(context, 'hubMargin'), paise: p.marginPaise, hidden: v.hidden, signed: true),
                      ]),
                    ]),
                  ),
              ],
              const HubRecordsOnly(),
            ],
          );
        },
      ),
    );
  }
}
