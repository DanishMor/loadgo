import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/offers/promo.dart';
import '../core/services/offers_switch_service.dart';
import '../core/services/rewards_service.dart';
import '../core/widgets/offers_gate.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/theme/design_tokens.dart';

String creditKindLabel(BuildContext context, String kind) => tr(context, switch (kind) {
      'spend' => 'creditSpend',
      'referral' => 'creditReferral',
      'admin_deduct' => 'creditDeduct',
      _ => 'creditGrant',
    });

/// Profile > Offers and credits: balance and history, the user's own
/// referral code, and a box to apply a friend's code.
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  final _applyCtrl = TextEditingController();
  late final Stream<List<CreditLine>> _credits = RewardsService.watchCredits().asBroadcastStream();
  String? _myCode;
  bool _referred = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!OffersSwitchService.current.referral) return;
      final code = await RewardsService.ensureReferralCode();
      final referred = await RewardsService.hasReferrer();
      if (mounted) {
        setState(() {
          _myCode = code;
          _referred = referred;
        });
      }
    } catch (_) {
      // Offline: the code appears when the screen is opened again.
    }
  }

  @override
  void dispose() {
    _applyCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final bonus = await RewardsService.applyReferral(_applyCtrl.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _referred = true;
      });
      showSnack(context, trf(context, 'referralApplied', {'amount': formatPaise(bonus)}));
    } on ReferralException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, tr(context, switch (e.problem) {
        ReferralProblem.unknownCode => 'referralUnknown',
        ReferralProblem.ownCode => 'referralOwn',
        ReferralProblem.alreadyReferred => 'referralAlready',
        ReferralProblem.tooLate => 'referralTooLate',
      }));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errorText(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: Text(tr(context, 'offersAndCredits'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          LiveStream<List<CreditLine>>(
            stream: () => _credits,
            builder: (context, lines) {
              final balance = CreditLine.balance(lines);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(context, 'creditBalance'), style: DsStyle.inherit.copyWith(color: AppColors.muted)),
                    Text(formatPaise(balance),
                        key: const ValueKey('creditBalance'),
                        style: DsStyle.t28w700.copyWith(color: AppColors.title)),
                    const SizedBox(height: 4),
                    Text(tr(context, 'offersRecordNote'), style: DsStyle.t12w400.copyWith(color: AppColors.faint)),
                  ]),
                ),
                OffersGate(test: (s) => s.referral, child: Padding(padding: const EdgeInsets.only(bottom: 16), child: _referralCard())),
                const SizedBox(height: 16),
                Text(tr(context, 'creditHistory'), style: DsStyle.t18w700),
                const SizedBox(height: 8),
                if (lines.isEmpty) Text(tr(context, 'noCreditLines'), style: DsStyle.inherit.copyWith(color: AppColors.muted)),
                for (final l in lines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(l.amountPaise >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                        color: l.amountPaise >= 0 ? AppColors.success : AppColors.warning),
                    title: Text(creditKindLabel(context, l.kind)),
                    subtitle: l.note.isEmpty ? null : Text(l.note),
                    trailing: Text('${l.amountPaise >= 0 ? '+' : '-'}${formatPaise(l.amountPaise.abs())}',
                        style: DsStyle.w700),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }

  Widget _referralCard() {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'yourReferralCode'), style: DsStyle.inherit.copyWith(color: AppColors.muted)),
        Row(children: [
          Expanded(
            child: Text(_myCode ?? '…',
                key: const ValueKey('myReferralCode'),
                style: DsStyle.t24w700.copyWith(letterSpacing: 2, color: AppColors.primary)),
          ),
          if (_myCode != null)
            IconButton(
              tooltip: tr(context, 'share'),
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: trf(context, 'referralShareText', {'code': _myCode!})));
                if (mounted) showSnack(context, tr(context, 'copiedToClipboard'));
              },
            ),
        ]),
        Text(tr(context, 'referralExplain'), style: DsStyle.t14w400.copyWith(color: AppColors.muted)),
        if (!_referred) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('referralInput'),
                controller: _applyCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: tr(context, 'haveReferralCode')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(key: const ValueKey('referralApply'), onPressed: _busy ? null : _apply, child: Text(tr(context, 'apply'))),
          ]),
        ],
      ]),
    );
  }
}
