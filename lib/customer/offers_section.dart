import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/offers/promo.dart';
import '../core/services/rewards_service.dart';
import '../core/widgets/common.dart';

/// Result of the offers block on Post Load: the promo to try (re-checked and
/// numbered when the load is posted) and the credits to spend.
class OffersChoice {
  final Promo? promo;
  final bool useCredits;
  const OffersChoice({this.promo, this.useCredits = false});
}

/// What the customer pays after offers, in paise (never below 0).
int payableAfterOffers({required int total, Promo? promo, int creditsBalance = 0, bool useCredits = false}) {
  final discount = promo?.discountFor(total) ?? 0;
  final left = total - discount;
  final credits = useCredits ? (creditsBalance < left ? creditsBalance : left) : 0;
  return left - (credits < 0 ? 0 : credits);
}

/// Credits that will be spent on an order of [total] with [promo].
int creditsToSpend({required int total, Promo? promo, required int creditsBalance, required bool useCredits}) {
  if (!useCredits || creditsBalance <= 0) return 0;
  final left = total - (promo?.discountFor(total) ?? 0);
  return left <= 0 ? 0 : (creditsBalance < left ? creditsBalance : left);
}

String promoProblemKey(PromoProblem p) => switch (p) {
      PromoProblem.unknown => 'promoUnknown',
      PromoProblem.inactive => 'promoInactive',
      PromoProblem.expired => 'promoExpired',
      PromoProblem.belowMinimum => 'promoBelowMinimum',
      PromoProblem.exhausted => 'promoExhausted',
      PromoProblem.usedUp => 'promoUsedUp',
    };

/// Promo code field + "use credits" switch for the Post Load form.
class OffersSection extends StatefulWidget {
  /// Estimated total of the order (paise), or null while there is no quote.
  final int? total;
  final ValueChanged<OffersChoice> onChanged;

  const OffersSection({super.key, required this.total, required this.onChanged});

  @override
  State<OffersSection> createState() => _OffersSectionState();
}

class _OffersSectionState extends State<OffersSection> {
  final _codeCtrl = TextEditingController();
  Promo? _promo;
  String? _error;
  bool _checking = false;
  bool _useCredits = false;
  int _balance = 0;

  @override
  void initState() {
    super.initState();
    RewardsService.balance().then((b) {
      if (mounted) setState(() => _balance = b);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(OffersChoice(promo: _promo, useCredits: _useCredits));

  Future<void> _apply() async {
    final total = widget.total;
    if (total == null) {
      setState(() => _error = tr(context, 'promoNeedsQuote'));
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final promo = await RewardsService.getPromo(_codeCtrl.text);
      final problem = promo == null ? PromoProblem.unknown : promo.problemFor(total, DateTime.now());
      if (!mounted) return;
      if (problem != null) {
        setState(() {
          _promo = null;
          _checking = false;
          _error = problem == PromoProblem.belowMinimum
              ? trf(context, 'promoBelowMinimum', {'min': formatPaise(promo!.minOrderPaise)})
              : tr(context, promoProblemKey(problem));
        });
      } else {
        setState(() {
          _promo = promo;
          _checking = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = tr(context, 'somethingWrong');
      });
    }
    _emit();
  }

  void _remove() {
    setState(() {
      _promo = null;
      _codeCtrl.clear();
      _error = null;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    final discount = total == null ? 0 : (_promo?.discountFor(total) ?? 0);
    // A code applied for a smaller order may stop fitting when the quote changes.
    final stale = _promo != null && total != null && _promo!.problemFor(total, DateTime.now()) != null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('promoCode'),
                controller: _codeCtrl,
                enabled: _promo == null,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.local_offer_outlined),
                  labelText: tr(context, 'promoCode'),
                  errorText: _error,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _promo == null
                ? FilledButton.tonal(
                    key: const ValueKey('promoApply'),
                    onPressed: _checking ? null : _apply,
                    child: Text(tr(context, 'apply')),
                  )
                : TextButton(key: const ValueKey('promoRemove'), onPressed: _remove, child: Text(tr(context, 'remove'))),
          ]),
          if (_promo != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                stale ? tr(context, 'promoNoLongerFits') : trf(context, 'promoApplied', {'amount': formatPaise(discount)}),
                key: const ValueKey('promoApplied'),
                style: TextStyle(color: stale ? AppColors.warning : AppColors.success, fontWeight: FontWeight.w700),
              ),
            ),
          if (_balance > 0)
            SwitchListTile(
              key: const ValueKey('useCredits'),
              contentPadding: EdgeInsets.zero,
              title: Text(trf(context, 'useCredits', {'amount': formatPaise(_balance)})),
              value: _useCredits,
              onChanged: (v) {
                setState(() => _useCredits = v);
                _emit();
              },
            ),
          if (total != null && (discount > 0 || _useCredits))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                trf(context, 'youPayAfterOffers', {
                  'amount': formatPaise(payableAfterOffers(total: total, promo: stale ? null : _promo, creditsBalance: _balance, useCredits: _useCredits)),
                }),
                key: const ValueKey('payableAfterOffers'),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.title),
              ),
            ),
          const SizedBox(height: 4),
          Text(tr(context, 'offersRecordNote'), style: const TextStyle(color: AppColors.faint, fontSize: 12)),
        ],
      ),
    );
  }
}
