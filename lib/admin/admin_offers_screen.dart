import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/offers/promo.dart';
import '../core/services/rewards_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

int? _rupeesToPaise(String s) {
  final n = double.tryParse(s.trim());
  return (n == null || n < 0) ? null : (n * 100).round();
}

String _promoSummary(BuildContext context, Promo p) {
  final value = p.type == Promo.percent ? '${p.value}%' : formatPaise(p.value);
  final cap = p.type == Promo.percent && p.maxDiscountPaise > 0 ? ' (≤ ${formatPaise(p.maxDiscountPaise)})' : '';
  return '$value$cap · ${trf(context, 'promoMinOrder', {'amount': formatPaise(p.minOrderPaise)})} · '
      '${formatDate(p.expiresAt)} · ${p.usageLimit}/${p.perUserLimit}';
}

/// Admin: promo codes, referral bonus and manual credit grants.
class AdminOffersScreen extends StatefulWidget {
  const AdminOffersScreen({super.key});

  @override
  State<AdminOffersScreen> createState() => _AdminOffersScreenState();
}

class _AdminOffersScreenState extends State<AdminOffersScreen> {
  final _bonusCtrl = TextEditingController();
  final _uidCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  late final Stream<List<Promo>> _promos = RewardsService.watchPromos().asBroadcastStream();

  @override
  void initState() {
    super.initState();
    RewardsService.referralBonus().then((b) {
      if (mounted) _bonusCtrl.text = (b / 100).toStringAsFixed(b % 100 == 0 ? 0 : 2);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _bonusCtrl.dispose();
    _uidCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveBonus() async {
    final paise = _rupeesToPaise(_bonusCtrl.text);
    if (paise == null) return showSnack(context, tr(context, 'invalidNumber'));
    await RewardsService.setReferralBonus(paise);
    if (mounted) showSnack(context, tr(context, 'settingsSaved'));
  }

  Future<void> _grant() async {
    final uid = _uidCtrl.text.trim();
    final negative = _amountCtrl.text.trim().startsWith('-');
    final paise = _rupeesToPaise(_amountCtrl.text.replaceFirst('-', ''));
    if (uid.isEmpty || paise == null || paise == 0) return showSnack(context, tr(context, 'invalidNumber'));
    await RewardsService.grantCredits(uid, negative ? -paise : paise, note: _noteCtrl.text);
    if (!mounted) return;
    _amountCtrl.clear();
    _noteCtrl.clear();
    showSnack(context, tr(context, 'settingsSaved'));
  }

  Future<void> _edit([Promo? p]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PromoEditScreen(existing: p)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: Text(tr(context, 'adminOffers'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('newPromo'),
        onPressed: _edit,
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'newPromo')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
        children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr(context, 'referralBonus'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('bonusRupees'),
                    controller: _bonusCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.currency_rupee_rounded)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(key: const ValueKey('saveBonus'), onPressed: _saveBonus, child: Text(tr(context, 'save'))),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr(context, 'grantCredits'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              TextField(key: const ValueKey('grantUid'), controller: _uidCtrl, decoration: InputDecoration(labelText: tr(context, 'userId'))),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('grantAmount'),
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: tr(context, 'grantAmountHint')),
              ),
              const SizedBox(height: 8),
              TextField(controller: _noteCtrl, maxLength: 200, decoration: InputDecoration(labelText: tr(context, 'noteOptional'))),
              FilledButton(key: const ValueKey('grantSubmit'), onPressed: _grant, child: Text(tr(context, 'grantCredits'))),
            ]),
          ),
          const SizedBox(height: 16),
          Text(tr(context, 'promoCodes'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          LiveStream<List<Promo>>(
            stream: () => _promos,
            builder: (context, promos) => Column(children: [
              if (promos.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'noPromos'))),
              for (final p in promos)
                ListTile(
                  key: ValueKey('promo_${p.code}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.code, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_promoSummary(context, p)),
                  trailing: Switch(
                    value: p.active,
                    onChanged: (v) => RewardsService.savePromo(Promo(
                      code: p.code, type: p.type, value: p.value, maxDiscountPaise: p.maxDiscountPaise,
                      minOrderPaise: p.minOrderPaise, expiresAt: p.expiresAt, usageLimit: p.usageLimit,
                      perUserLimit: p.perUserLimit, active: v,
                    )),
                  ),
                  onTap: () => _edit(p),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Create or edit one promo code. Amounts are typed in rupees.
class PromoEditScreen extends StatefulWidget {
  final Promo? existing;
  const PromoEditScreen({super.key, this.existing});

  @override
  State<PromoEditScreen> createState() => _PromoEditScreenState();
}

class _PromoEditScreenState extends State<PromoEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late String _type = widget.existing?.type ?? Promo.percent;
  late final _value = TextEditingController(
      text: widget.existing == null ? '' : (_type == Promo.percent ? '${widget.existing!.value}' : '${widget.existing!.value / 100}'));
  late final _max = TextEditingController(text: widget.existing == null ? '' : '${widget.existing!.maxDiscountPaise / 100}');
  late final _min = TextEditingController(text: widget.existing == null ? '0' : '${widget.existing!.minOrderPaise / 100}');
  late final _days = TextEditingController(text: '30');
  late final _limit = TextEditingController(text: '${widget.existing?.usageLimit ?? 100}');
  late final _perUser = TextEditingController(text: '${widget.existing?.perUserLimit ?? 1}');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_code, _value, _max, _min, _days, _limit, _perUser]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _int(String? v, int min, int max) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n < min || n > max) ? tr(context, 'invalidNumber') : null;
  }

  String? _rupees(String? v, {bool allowEmpty = false}) {
    if (allowEmpty && (v ?? '').trim().isEmpty) return null;
    return _rupeesToPaise(v ?? '') == null ? tr(context, 'invalidNumber') : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final isPercent = _type == Promo.percent;
      await RewardsService.savePromo(Promo(
        code: Promo.normaliseCode(_code.text),
        type: _type,
        value: isPercent ? int.parse(_value.text.trim()) : _rupeesToPaise(_value.text)!,
        maxDiscountPaise: _rupeesToPaise(_max.text) ?? 0,
        minOrderPaise: _rupeesToPaise(_min.text) ?? 0,
        expiresAt: widget.existing != null && _days.text.trim() == '0'
            ? widget.existing!.expiresAt
            : DateTime.now().add(Duration(days: int.parse(_days.text.trim()))),
        usageLimit: int.parse(_limit.text.trim()),
        perUserLimit: int.parse(_perUser.text.trim()),
        active: widget.existing?.active ?? true,
      ));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPercent = _type == Promo.percent;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'newPromo'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          TextFormField(
            key: const ValueKey('promoCodeField'),
            controller: _code,
            enabled: widget.existing == null,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
            decoration: InputDecoration(labelText: tr(context, 'promoCode')),
            validator: (v) => Promo.validCode(Promo.normaliseCode(v ?? '')) ? null : tr(context, 'promoCodeFormat'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: Promo.percent, label: Text(tr(context, 'promoPercent'))),
              ButtonSegment(value: Promo.flat, label: Text(tr(context, 'promoFlat'))),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('promoValue'),
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr(context, isPercent ? 'promoPercentValue' : 'promoFlatValue')),
            validator: (v) => isPercent ? _int(v, 1, 100) : (_rupees(v) ?? (_rupeesToPaise(v ?? '') == 0 ? tr(context, 'invalidNumber') : null)),
          ),
          TextFormField(
            key: const ValueKey('promoMax'),
            controller: _max,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr(context, 'promoMaxDiscount')),
            validator: (v) => _rupees(v, allowEmpty: true),
          ),
          TextFormField(
            key: const ValueKey('promoMin'),
            controller: _min,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr(context, 'promoMinOrderField')),
            validator: (v) => _rupees(v),
          ),
          TextFormField(
            key: const ValueKey('promoDays'),
            controller: _days,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr(context, 'promoValidDays')),
            validator: (v) => _int(v, widget.existing == null ? 1 : 0, 730),
          ),
          TextFormField(
            key: const ValueKey('promoLimit'),
            controller: _limit,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr(context, 'promoUsageLimit')),
            validator: (v) => _int(v, 1, 100000),
          ),
          TextFormField(
            key: const ValueKey('promoPerUser'),
            controller: _perUser,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr(context, 'promoPerUserLimit')),
            validator: (v) => _int(v, 1, 100),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: tr(context, 'save'), loading: _saving, onPressed: _save),
        ]),
      ),
    );
  }
}
