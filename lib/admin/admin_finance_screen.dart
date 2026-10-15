import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors/error_text.dart';
import '../core/l10n/l10n.dart';
import '../core/models/ledger_entry.dart';
import '../core/models/payout.dart';
import '../core/services/backend.dart';
import '../core/services/finance_service.dart';
import '../core/theme/design_tokens.dart';
import '../core/wallet/finance/finance_logic.dart';
import '../core/widgets/common.dart';
import '../core/widgets/ds/app_button.dart';
import '../core/widgets/ds/money_text.dart';
import '../core/widgets/live_stream.dart';

/// Admin Finance (F12, staff roles finance and super). Payout queue with
/// maker-checker, the daily check of ledger against payouts and summaries,
/// anomaly flags, freeze and correction tools, CSV copy. Nothing moves real
/// money; every action is audited and the rules enforce who may do what.
class AdminFinanceScreen extends StatefulWidget {
  final Stream<List<Payout>> Function() payouts;
  final Stream<List<LedgerEntry>> Function() ledger;
  final Stream<Map<String, int>> Function() summaries;
  final Stream<Map<String, DateTime>> Function() detailsChanged;
  final String? Function() me;
  final DateTime Function() now;

  const AdminFinanceScreen({
    super.key,
    this.payouts = FinanceService.watchPayouts,
    this.ledger = FinanceService.watchLedger,
    this.summaries = FinanceService.watchSummaries,
    this.detailsChanged = FinanceService.watchDetailsChanged,
    this.me = _myUid,
    this.now = DateTime.now,
  });

  static String? _myUid() => Backend.uid;

  @override
  State<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends State<AdminFinanceScreen> {
  PayoutStage _stage = PayoutStage.waitingApproval;
  bool _busy = false;

  Future<String?> _ask(String titleKey, String labelKey, {bool number = false, int maxLength = 200}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, titleKey)),
        content: TextField(
          key: const ValueKey('finDialogField'),
          controller: ctrl,
          autofocus: true,
          maxLength: maxLength,
          keyboardType: number ? const TextInputType.numberWithOptions(signed: true, decimal: true) : TextInputType.text,
          decoration: InputDecoration(labelText: tr(context, labelKey)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
          FilledButton(key: const ValueKey('finDialogOk'), onPressed: () => Navigator.pop(context, ctrl.text), child: Text(tr(context, titleKey))),
        ],
      ),
    );
    return result;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSnack(context, tr(context, 'statusUpdated'));
    } on FinanceException catch (e) {
      if (mounted) showSnack(context, tr(context, e.key));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _anomalyKey(AnomalyKind k) => switch (k) {
        AnomalyKind.bigPayout => 'finAnomalyBig',
        AnomalyKind.newAccountBig => 'finAnomalyNew',
        AnomalyKind.manyInOneDay => 'finAnomalyMany',
      };

  Widget _stageLabel(PayoutStage s) => Text(tr(context, switch (s) {
        PayoutStage.waitingApproval => 'finStageApproval',
        PayoutStage.waitingPayment => 'finStagePayment',
        PayoutStage.done => 'finStageDone',
        PayoutStage.closed => 'finStageClosed',
      }));

  Widget _queue() {
    return LiveStream<List<Payout>>(
      stream: widget.payouts,
      builder: (context, all) => LiveStream<Map<String, DateTime>>(
        stream: widget.detailsChanged,
        compact: true,
        builder: (context, changed) {
          final c = context.ds;
          final me = widget.me();
          final anomalies = AnomalyRules.detect(all, detailsChangedAt: changed, now: widget.now());
          final byPayout = <String, List<Anomaly>>{};
          for (final a in anomalies) {
            byPayout.putIfAbsent(a.payoutId, () => []).add(a);
          }
          final shown = [for (final p in all) if (stageOf(p) == _stage) p];
          int sum(Iterable<Payout> l) => l.fold(0, (a, p) => a + p.amountPaise);
          return ListView(
            padding: const EdgeInsets.all(DsSpace.gutter),
            children: [
              Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
                for (final s in PayoutStage.values)
                  ChoiceChip(
                    key: ValueKey('finStage_${s.name}'),
                    label: _stageLabel(s),
                    selected: _stage == s,
                    onSelected: (_) => setState(() => _stage = s),
                  ),
              ]),
              const SizedBox(height: DsSpace.s3),
              Text('${shown.length} · ${formatPaise(sum(shown))}', key: const ValueKey('finStageTotal'), style: DsType.caption.copyWith(color: c.textMuted)),
              if (shown.isEmpty) Padding(padding: const EdgeInsets.all(DsSpace.s8), child: Center(child: Text(tr(context, 'finEmpty')))),
              for (final p in shown)
                AppCard(
                  key: ValueKey('finPayout_${p.id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: DsSpace.s3, runSpacing: DsSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      MoneyText(p.amountPaise, size: MoneySize.large),
                      StatusChip(label: tr(context, 'payout_${p.status}'), color: AppColors.warning),
                    ]),
                    Text('${p.driverId}${p.createdAt == null ? '' : ' · ${formatDateTime(p.createdAt!)}'}', style: DsType.caption.copyWith(color: c.textMuted)),
                    if (p.reference != null) Text(p.reference!, key: ValueKey('finRef_${p.id}'), style: DsType.caption.copyWith(color: c.textMuted)),
                    if (byPayout[p.id] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: DsSpace.s2),
                        child: Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, children: [
                          for (final a in {...byPayout[p.id]!.map((x) => x.kind)})
                            Chip(
                              key: ValueKey('finAnomaly_${p.id}_${a.name}'),
                              avatar: Icon(Icons.warning_amber_rounded, size: 18, color: c.error),
                              label: Text(tr(context, _anomalyKey(a))),
                            ),
                        ]),
                      ),
                    if (PayoutActions.whyNotPay(p, me) != null)
                      Padding(
                        padding: const EdgeInsets.only(top: DsSpace.s2),
                        child: Text(tr(context, PayoutActions.whyNotPay(p, me)!), key: ValueKey('finWhy_${p.id}'), style: DsType.caption.copyWith(color: c.textMuted)),
                      ),
                    const SizedBox(height: DsSpace.s2),
                    Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
                      if (PayoutActions.canApprove(p))
                        AppButton(key: ValueKey('finApprove_${p.id}'), label: tr(context, 'finApprove'), expand: false, loading: _busy, onPressed: () => _run(() => FinanceService.approve(p))),
                      if (PayoutActions.canPay(p, me))
                        AppButton(
                          key: ValueKey('finPay_${p.id}'),
                          label: tr(context, 'finPay'),
                          expand: false,
                          loading: _busy,
                          onPressed: () async {
                            final ref = await _ask('finPay', 'finReference', maxLength: 60);
                            if (ref != null) await _run(() => FinanceService.pay(p, ref));
                          },
                        ),
                      if (PayoutActions.canReject(p))
                        AppButton(
                          key: ValueKey('finReject_${p.id}'),
                          label: tr(context, 'reject'),
                          kind: AppButtonKind.secondary,
                          expand: false,
                          loading: _busy,
                          onPressed: () async {
                            final reason = await _ask('reject', 'finReason');
                            if (reason != null) await _run(() => FinanceService.reject(p, reason));
                          },
                        ),
                      if (PayoutActions.canReverse(p))
                        AppButton(
                          key: ValueKey('finReverse_${p.id}'),
                          label: tr(context, 'finReverse'),
                          kind: AppButtonKind.danger,
                          expand: false,
                          loading: _busy,
                          onPressed: () async {
                            final reason = await _ask('finReverse', 'finReason');
                            if (reason != null) await _run(() => FinanceService.reverse(p, reason));
                          },
                        ),
                    ]),
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _recon() {
    return LiveStream<List<LedgerEntry>>(
      stream: widget.ledger,
      builder: (context, ledger) => LiveStream<List<Payout>>(
        stream: widget.payouts,
        compact: true,
        builder: (context, payouts) => LiveStream<Map<String, int>>(
          stream: widget.summaries,
          compact: true,
          builder: (context, summaries) {
            final c = context.ds;
            final r = Reconciliation.run(ledger: ledger, payouts: payouts, summaries: summaries);
            final problems = r.problems;
            return ListView(
              padding: const EdgeInsets.all(DsSpace.gutter),
              children: [
                AppCard(
                  child: Wrap(spacing: DsSpace.s6, runSpacing: DsSpace.s3, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(tr(context, 'finOwed'), style: DsType.caption.copyWith(color: c.textMuted)),
                      KeyedSubtree(key: const ValueKey('finOwed'), child: MoneyText(r.owedPaise, size: MoneySize.large)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(tr(context, 'finPaidOut'), style: DsType.caption.copyWith(color: c.textMuted)),
                      KeyedSubtree(key: const ValueKey('finPaidOutTotal'), child: MoneyText(r.paidOutPaise, size: MoneySize.large)),
                    ]),
                  ]),
                ),
                const SizedBox(height: DsSpace.s3),
                if (problems.isEmpty)
                  Text(tr(context, 'finReconOk'), key: const ValueKey('finReconOk'), style: DsType.body.copyWith(color: c.success))
                else ...[
                  Text(tr(context, 'finReconProblems'), style: DsType.title.copyWith(color: c.text)),
                  for (final x in problems)
                    AppCard(
                      key: ValueKey('finRecon_${x.driverId}'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.driverId, style: DsType.body.copyWith(color: c.text)),
                        if (!x.balanced) Text(tr(context, 'finNotBalanced'), style: DsType.caption.copyWith(color: c.error)),
                        if (x.overdrawn) Text(tr(context, 'finOverdrawn'), style: DsType.caption.copyWith(color: c.error)),
                        if (x.summaryMismatch) Text(tr(context, 'finSummaryMismatch'), style: DsType.caption.copyWith(color: c.error)),
                        MoneyText(x.balance.available.paise, size: MoneySize.small, signed: true),
                      ]),
                    ),
                ],
                const SizedBox(height: DsSpace.s3),
                AppButton(
                  key: const ValueKey('finCopyRecon'),
                  label: tr(context, 'finCopyCsv'),
                  kind: AppButtonKind.secondary,
                  icon: Icons.copy_rounded,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: r.toCsv()));
                    if (context.mounted) showSnack(context, tr(context, 'finCopied'));
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  final _uid = TextEditingController();
  final _reason = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _uid.dispose();
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  Widget _tools() {
    return ListView(
      padding: const EdgeInsets.all(DsSpace.gutter),
      children: [
        TextField(key: const ValueKey('finUser'), controller: _uid, decoration: InputDecoration(labelText: tr(context, 'finUserId'))),
        const SizedBox(height: DsSpace.s3),
        TextField(key: const ValueKey('finReasonField'), controller: _reason, maxLength: 200, decoration: InputDecoration(labelText: tr(context, 'finReason'))),
        const SizedBox(height: DsSpace.s2),
        Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
          AppButton(key: const ValueKey('finFreeze'), label: tr(context, 'finFreeze'), kind: AppButtonKind.danger, expand: false, loading: _busy, onPressed: () => _run(() => FinanceService.setFrozen(_uid.text, true, _reason.text))),
          AppButton(key: const ValueKey('finUnfreeze'), label: tr(context, 'finUnfreeze'), kind: AppButtonKind.secondary, expand: false, loading: _busy, onPressed: () => _run(() => FinanceService.setFrozen(_uid.text, false, _reason.text))),
        ]),
        const SizedBox(height: DsSpace.s6),
        TextField(
          key: const ValueKey('finAmountField'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
          decoration: InputDecoration(labelText: tr(context, 'finAmount'), prefixIcon: const Icon(Icons.currency_rupee_rounded)),
        ),
        const SizedBox(height: DsSpace.s2),
        AppButton(
          key: const ValueKey('finAdjust'),
          label: tr(context, 'finAdjust'),
          expand: false,
          loading: _busy,
          onPressed: () => _run(() async {
            final t = _amount.text.trim().replaceAll(',', '');
            final m = RegExp(r'^(-?)(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(t);
            if (m == null) throw const FinanceException('finNeedAmount');
            final paise = int.parse(m.group(2)!) * 100 + (m.group(3) == null ? 0 : int.parse(m.group(3)!.padRight(2, '0')));
            await FinanceService.adjust(_uid.text, m.group(1) == '-' ? -paise : paise, _reason.text);
          }),
        ),
        const SizedBox(height: DsSpace.s6),
        LiveStream<List<Payout>>(
          stream: widget.payouts,
          compact: true,
          builder: (context, all) => AppButton(
            key: const ValueKey('finCopyQueue'),
            label: tr(context, 'finCopyCsv'),
            kind: AppButtonKind.secondary,
            icon: Icons.copy_rounded,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: payoutQueueCsv(all)));
              if (context.mounted) showSnack(context, tr(context, 'finCopied'));
            },
          ),
        ),
        const SizedBox(height: DsSpace.s8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'adminFinance')),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(key: const ValueKey('finTabQueue'), text: tr(context, 'finTabQueue')),
              Tab(key: const ValueKey('finTabRecon'), text: tr(context, 'finTabRecon')),
              Tab(key: const ValueKey('finTabTools'), text: tr(context, 'finTabTools')),
            ],
          ),
        ),
        body: TabBarView(children: [_queue(), _recon(), _tools()]),
      ),
    );
  }
}
