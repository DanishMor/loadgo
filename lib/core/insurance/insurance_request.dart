import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../adapters/adapters.dart';
import '../features/features.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/backend.dart';
import '../services/features_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';

/// E32 (legal gate legalGateInsurance, OFF in every mode until the owner's legal check and an insurer partner):
/// the customer can ask an insurance partner for a cargo cover QUOTE on a booking. The app sells nothing, promises
/// no cover and holds no money; the partner answers the customer directly. Calls go through ConnectKit and its cost
/// guard; with no partner configured the customer is told so and nothing is sent.
class InsuranceRequests {
  InsuranceRequests._();

  /// The adapter: the real one only when the gate is ON and the provider is configured (no real one is built yet).
  static InsuranceQuotes adapter = const NoInsuranceQuotes();
  static final CostGuard guard = ConnectKit.guard('insurance', () => FeaturesService.notifier.value, const ProviderConfig());

  /// The highest goods value a request may carry (₹1 crore), a sanity bound, not an insurer limit.
  static const maxValuePaise = 1000000000;
}

/// The outcome of one request, for the words shown.
enum InsuranceOutcome { sent, notConnected, capped, invalid, failed }

Future<InsuranceOutcome> requestCargoQuote({required String bookingId, required String goods, required int valuePaise, InsuranceQuotes? via, CostGuard? guard}) async {
  if (valuePaise <= 0 || valuePaise > InsuranceRequests.maxValuePaise || goods.trim().isEmpty || bookingId.isEmpty) return InsuranceOutcome.invalid;
  final denied = (guard ?? InsuranceRequests.guard).take(Backend.uid ?? 'anon');
  if (denied != null) return InsuranceOutcome.capped;
  try {
    final r = await (via ?? InsuranceRequests.adapter).requestQuote(cargoValuePaise: valuePaise, goods: goods.trim(), bookingId: bookingId);
    if (r.ok) return InsuranceOutcome.sent;
    return switch (r.failure) {
      ConnectFailure.notConfigured => InsuranceOutcome.notConnected,
      ConnectFailure.invalidInput => InsuranceOutcome.invalid,
      ConnectFailure.capped => InsuranceOutcome.capped,
      _ => InsuranceOutcome.failed,
    };
  } catch (_) {
    return InsuranceOutcome.failed;
  }
}

/// On a running booking: "Ask for goods insurance", shown only behind the legal gate.
class InsuranceRequestCard extends StatelessWidget {
  final Booking booking;
  final InsuranceQuotes? via;
  const InsuranceRequestCard({super.key, required this.booking, this.via});

  @override
  Widget build(BuildContext context) {
    if (!FeaturesService.isOn(FeatureKey.legalGateInsurance)) return const SizedBox.shrink();
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s2),
      child: AppCard(
        key: const ValueKey('insCard'),
        onTap: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _InsuranceSheet(booking: booking, via: via)),
        child: Row(children: [
          Icon(Icons.shield_outlined, color: c.primary),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'insTitle'), style: DsType.subtitle.copyWith(color: c.textStrong)),
              Text(tr(context, 'insSub'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}

class _InsuranceSheet extends StatefulWidget {
  final Booking booking;
  final InsuranceQuotes? via;
  const _InsuranceSheet({required this.booking, this.via});

  @override
  State<_InsuranceSheet> createState() => _InsuranceSheetState();
}

class _InsuranceSheetState extends State<_InsuranceSheet> {
  late final _goods = TextEditingController(text: widget.booking.cargoType);
  final _value = TextEditingController();
  bool _understood = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _goods.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final rupees = int.tryParse(_value.text.trim());
    setState(() {
      _busy = true;
      _message = null;
    });
    final out = await requestCargoQuote(bookingId: widget.booking.id, goods: _goods.text, valuePaise: (rupees ?? 0) * 100, via: widget.via);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = tr(context, 'insOut_${out.name}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(DsSpace.gutter, 0, DsSpace.gutter, DsSpace.gutter + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(header: true, child: Text(tr(context, 'insTitle'), style: DsType.title.copyWith(color: c.textStrong))),
          const SizedBox(height: DsSpace.s2),
          Container(
            key: const ValueKey('insDisclaimer'),
            padding: const EdgeInsets.all(DsSpace.s3),
            decoration: BoxDecoration(color: c.warningBg, borderRadius: DsRadius.all(DsRadius.lg)),
            child: Text(tr(context, 'insDisclaimer'), style: DsType.bodySmall.copyWith(color: c.text)),
          ),
          const SizedBox(height: DsSpace.s3),
          TextField(key: const ValueKey('insGoods'), controller: _goods, decoration: InputDecoration(labelText: tr(context, 'qsGoods')), inputFormatters: [LengthLimitingTextInputFormatter(80)]),
          TextField(
            key: const ValueKey('insValue'),
            controller: _value,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
            decoration: InputDecoration(labelText: tr(context, 'insValue'), prefixText: '₹ '),
          ),
          CheckboxListTile(
            key: const ValueKey('insUnderstood'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _understood,
            onChanged: (v) => setState(() => _understood = v ?? false),
            title: Text(tr(context, 'insUnderstood'), style: DsType.bodySmall.copyWith(color: c.text)),
          ),
          if (_message != null) Padding(padding: const EdgeInsets.only(bottom: DsSpace.s2), child: Text(_message!, key: const ValueKey('insMessage'), style: DsType.body.copyWith(color: c.textStrong))),
          AppButton(key: const ValueKey('insSend'), label: tr(context, 'insSend'), loading: _busy, onPressed: _understood && !_busy ? _send : null),
        ]),
      ),
    );
  }
}
