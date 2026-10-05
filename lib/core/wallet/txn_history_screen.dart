import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/driver_extras.dart';
import '../models/ledger_entry.dart';
import '../models/payout.dart';
import '../offers/promo.dart';
import '../services/booking_service.dart';
import '../services/driver_extras_service.dart';
import '../services/payment_service.dart';
import '../services/payout_service.dart';
import '../services/rewards_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import 'txn_history.dart';

/// Money in and out for the signed-in customer or driver, with filters and a
/// CSV copy. Records only: no money moves through LoadGo.
class TxnHistoryScreen extends StatefulWidget {
  final bool isDriver;

  const TxnHistoryScreen({super.key, required this.isDriver});

  @override
  State<TxnHistoryScreen> createState() => _TxnHistoryScreenState();
}

class _TxnHistoryScreenState extends State<TxnHistoryScreen> {
  final _kinds = <String>{};
  TxnDirection _direction = TxnDirection.all;
  int? _days; // null = all time

  /// Latest value of each source, merged into one list.
  late final Stream<List<TxnLine>> _lines = (widget.isDriver
          ? _combine3<LedgerEntry, Payout, Tip>(
              PaymentService.watchLedger(), PayoutService.watchMine(), DriverExtrasService.watchMyTips(),
              (a, b, c) => TxnHistory.forDriver(ledger: a, payouts: b, tips: c))
          : _combine3<Booking, Tip, CreditLine>(
              BookingService.watchForCustomer(), DriverExtrasService.watchGivenTips(), RewardsService.watchCredits(),
              (a, b, c) => TxnHistory.forCustomer(bookings: a, tips: b, credits: c)))
      .asBroadcastStream();

  TxnFilter get _filter => TxnFilter(
        kinds: _kinds,
        direction: _direction,
        from: _days == null ? null : DateTime.now().subtract(Duration(days: _days!)),
      );

  List<String> get _availableKinds => widget.isDriver
      ? [TxnKind.earning, TxnKind.commission, TxnKind.payout, TxnKind.tip]
      : [TxnKind.trip, TxnKind.tip, TxnKind.credit];

  Widget _total(String label, int paise, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          Text(formatPaise(paise), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'txnTitle'))),
      body: LiveStream<List<TxnLine>>(
        stream: () => _lines,
        builder: (context, all) {
          final shown = TxnHistory.apply(all, _filter);
          final sum = TxnHistory.summary(shown);
          return ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), children: [
            Wrap(spacing: 8, children: [
              for (final k in _availableKinds)
                FilterChip(
                  key: ValueKey('txnKind_$k'),
                  label: Text(tr(context, 'txnKind_$k')),
                  selected: _kinds.contains(k),
                  onSelected: (on) => setState(() => on ? _kinds.add(k) : _kinds.remove(k)),
                ),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<TxnDirection>(
              key: const ValueKey('txnDirection'),
              segments: [
                ButtonSegment(value: TxnDirection.all, label: Text(tr(context, 'txnAll'))),
                ButtonSegment(value: TxnDirection.moneyIn, label: Text(tr(context, 'txnIn'))),
                ButtonSegment(value: TxnDirection.moneyOut, label: Text(tr(context, 'txnOut'))),
              ],
              selected: {_direction},
              onSelectionChanged: (v) => setState(() => _direction = v.first),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int?>(
              key: const ValueKey('txnPeriod'),
              segments: [
                ButtonSegment(value: 30, label: Text(tr(context, 'txnPeriod_30'))),
                ButtonSegment(value: 90, label: Text(tr(context, 'txnPeriod_90'))),
                ButtonSegment(value: null, label: Text(tr(context, 'txnPeriod_all'))),
              ],
              selected: {_days},
              onSelectionChanged: (v) => setState(() => _days = v.first),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Row(children: [
                _total(tr(context, 'txnIn'), sum.moneyIn, AppColors.success),
                _total(tr(context, 'txnOut'), -sum.moneyOut, Colors.redAccent),
                _total(tr(context, 'txnNet'), sum.net, AppColors.title),
              ]),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('txnCsv'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: TxnHistory.toCsv(shown)));
                  if (context.mounted) showSnack(context, tr(context, 'csvCopied'));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(tr(context, 'txnCopyCsv')),
              ),
            ),
            if (shown.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(tr(context, 'txnNone'), style: const TextStyle(color: AppColors.muted))),
            for (final l in shown)
              ListTile(
                key: ValueKey('txn_${l.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(l.isIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: l.isIn ? AppColors.success : Colors.redAccent),
                title: Text(tr(context, 'txnKind_${l.kind}')),
                subtitle: Text([
                  if (l.bookingId.isNotEmpty) 'LG-${l.bookingId.length > 10 ? l.bookingId.substring(0, 10).toUpperCase() : l.bookingId.toUpperCase()}',
                  formatDateTime(l.date),
                  if (l.pending) tr(context, 'txnPending'),
                ].join(' • ')),
                trailing: Text(formatPaise(l.amountPaise), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]);
        },
      ),
    );
  }
}

/// Re-emits [f] over the latest value of three streams once all have spoken.
Stream<List<TxnLine>> _combine3<A, B, C>(
  Stream<List<A>> a,
  Stream<List<B>> b,
  Stream<List<C>> c,
  List<TxnLine> Function(List<A>, List<B>, List<C>) f,
) {
  List<A>? la;
  List<B>? lb;
  List<C>? lc;
  final subs = <StreamSubscription<Object?>>[];
  late StreamController<List<TxnLine>> out;
  void emit() {
    if (la != null && lb != null && lc != null) out.add(f(la!, lb!, lc!));
  }

  out = StreamController<List<TxnLine>>(
    onListen: () {
      subs.add(a.listen((v) {
        la = v;
        emit();
      }, onError: out.addError));
      subs.add(b.listen((v) {
        lb = v;
        emit();
      }, onError: out.addError));
      subs.add(c.listen((v) {
        lc = v;
        emit();
      }, onError: out.addError));
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return out.stream;
}
