import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../support/support_screens.dart';
import '../widgets/common.dart';
import 'assistant_engine.dart';
import 'assistant_log_service.dart';

/// What the role's home can open for the assistant's action buttons. A null
/// callback hides that button. The ticket form is in core and needs none.
class SahayakActions {
  final VoidCallback? openBookings;
  final void Function(Map<String, String> prefill)? openPostLoad;
  final VoidCallback? openNearbyLoads;
  const SahayakActions({this.openBookings, this.openPostLoad, this.openNearbyLoads});
}

class _Msg {
  final bool mine;
  final String? text;
  final AssistantReply? reply;
  const _Msg.user(String this.text)
      : mine = true,
        reply = null;
  const _Msg.bot(AssistantReply this.reply)
      : mine = false,
        text = null;
}

/// LoadGo Sahayak: a small chat with action buttons, used by both apps.
class SahayakScreen extends StatefulWidget {
  /// `customer` or `driver`.
  final String role;
  final SahayakActions actions;
  final AssistantEngine engine;

  /// Writes unknown questions to the admin log. Tests switch it off.
  final bool logUnknown;

  const SahayakScreen({
    super.key,
    required this.role,
    this.actions = const SahayakActions(),
    this.engine = const RuleEngine(),
    this.logUnknown = true,
  });

  @override
  State<SahayakScreen> createState() => _SahayakScreenState();
}

class _SahayakScreenState extends State<SahayakScreen> {
  static const maxInput = 200;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late final List<_Msg> _msgs = [
    const _Msg.bot(AssistantReply(intent: AssistantIntent.greeting, textKey: 'asGreeting')),
  ];

  // (label key, text the engine reads)
  List<(String, String)> get _chips => widget.role == 'driver'
      ? const [
          ('asChipNearby', 'nearby loads'),
          ('asChipBid', 'bid'),
          ('asChipOtp', 'otp'),
          ('asChipPay', 'payment'),
          ('asChipBooking', 'my booking'),
        ]
      : const [
          ('asChipPost', 'post load'),
          ('asChipBooking', 'my booking'),
          ('asChipOtp', 'otp'),
          ('asChipPay', 'payment'),
          ('asChipCancel', 'cancel'),
        ];

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String shown, {String? query}) {
    final text = shown.trim();
    if (text.isEmpty) return;
    final reply = widget.engine.reply(query ?? text, role: widget.role);
    setState(() {
      _msgs.add(_Msg.user(text));
      _msgs.add(_Msg.bot(reply));
    });
    _ctrl.clear();
    if (widget.logUnknown && query == null) {
      AssistantLogService.logUnknown(text, reply, role: widget.role, language: languageNotifier.value.name);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  void _run(AssistantReply r) {
    final a = widget.actions;
    switch (r.action) {
      case AssistantAction.openTicket:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewTicketScreen()));
      case AssistantAction.openBookings:
        Navigator.of(context).pop();
        a.openBookings?.call();
      case AssistantAction.openNearbyLoads:
        Navigator.of(context).pop();
        a.openNearbyLoads?.call();
      case AssistantAction.openPostLoad:
        Navigator.of(context).pop();
        a.openPostLoad?.call(r.prefill);
      case AssistantAction.none:
        break;
    }
  }

  /// Label key of the action button, or null when this role cannot do it.
  String? _actionLabel(AssistantReply r) {
    final a = widget.actions;
    return switch (r.action) {
      AssistantAction.openTicket => 'asBtnTicket',
      AssistantAction.openBookings => a.openBookings == null ? null : 'asBtnBookings',
      AssistantAction.openNearbyLoads => a.openNearbyLoads == null ? null : 'asBtnNearby',
      AssistantAction.openPostLoad => a.openPostLoad == null ? null : 'asBtnPostLoad',
      AssistantAction.none => null,
    };
  }

  Widget _bubble(_Msg m) {
    if (m.mine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
          child: Text(m.text!, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    final r = m.reply!;
    final label = _actionLabel(r);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 48),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, r.textKey), style: TextStyle(color: AppColors.title)),
          if (label != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              key: ValueKey('asAction_${r.action.name}'),
              onPressed: () => _run(r),
              child: Text(tr(context, label)),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(tr(context, 'asTitle'))),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView.builder(
              key: const ValueKey('asList'),
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _msgs.length,
              itemBuilder: (_, i) => _bubble(_msgs[i]),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (key, query) in _chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      key: ValueKey('asChip_$key'),
                      label: Text(tr(context, key)),
                      onPressed: () => _send(tr(context, key), query: query),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('asInput'),
                  controller: _ctrl,
                  textInputAction: TextInputAction.send,
                  inputFormatters: [LengthLimitingTextInputFormatter(maxInput)],
                  onSubmitted: _send,
                  decoration: InputDecoration(hintText: tr(context, 'asHint'), border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const ValueKey('asSend'),
                tooltip: tr(context, 'asSend'),
                onPressed: () => _send(_ctrl.text),
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// App bar button that opens Sahayak.
class SahayakButton extends StatelessWidget {
  final String role;
  final SahayakActions actions;
  const SahayakButton({super.key, required this.role, required this.actions});

  @override
  Widget build(BuildContext context) => IconButton(
        key: const ValueKey('sahayakButton'),
        tooltip: tr(context, 'asTitle'),
        color: const Color(0xFF1565C0),
        icon: const Icon(Icons.support_agent_rounded),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SahayakScreen(role: role, actions: actions))),
      );
}
