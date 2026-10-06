import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/driver_network.dart';
import '../services/backend.dart';
import '../services/network_service.dart';
import '../services/rate_limit_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import 'network_logic.dart';

/// Chat of a driver connection ([kind] `link`, CH2) or a group (`group`, CH3).
/// A message can carry a load card (CH7).
class NetworkChatScreen extends StatelessWidget {
  final String kind;
  final String id;
  final String title;
  const NetworkChatScreen({super.key, required this.kind, required this.id, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: NetworkChatBody(kind: kind, id: id),
    );
  }
}

class NetworkChatBody extends StatefulWidget {
  final String kind;
  final String id;
  const NetworkChatBody({super.key, required this.kind, required this.id});

  @override
  State<NetworkChatBody> createState() => _NetworkChatBodyState();
}

class _NetworkChatBodyState extends State<NetworkChatBody> {
  final _ctrl = TextEditingController();
  late final Stream<List<NetworkMessage>> _messages = NetworkService.watchMessages(widget.kind, widget.id);
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await NetworkService.send(widget.kind, widget.id, senderName: await NetworkService.myName(), text: text);
      _ctrl.clear();
    } on RateLimitException catch (e) {
      if (mounted) showSnack(context, trf(context, 'rateLimited', {'m': e.minutesLeft}));
    } catch (_) {
      if (mounted) showRetrySnack(context, tr(context, 'somethingWrong'), _send);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _bubble(NetworkMessage m) {
    final mine = m.senderId == Backend.uid;
    final fg = mine ? Colors.white : AppColors.title;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey('netMsg_${m.id}'),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine && m.senderName.isNotEmpty)
              Text(m.senderName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
            if (m.loadCard != null) SharedLoadCardView(card: m.loadCard!),
            if (m.text.isNotEmpty) Text(m.text, style: TextStyle(color: fg)),
            if (m.flagged)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr(context, 'flaggedMessage'), style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : AppColors.warning)),
              ),
            if (m.createdAt != null) Text(formatDateTime(m.createdAt!), style: TextStyle(fontSize: 10, color: mine ? Colors.white60 : AppColors.faint)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.warnBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(tr(context, 'offPlatformWarning'), style: TextStyle(fontSize: 12, color: AppColors.body)),
            ),
            Expanded(
              child: LiveStream<List<NetworkMessage>>(
                stream: () => _messages,
                builder: (context, list) {
                  if (list.isEmpty) return Center(child: Text(tr(context, 'netSayHello'), style: TextStyle(color: AppColors.muted)));
                  return ListView(reverse: true, padding: const EdgeInsets.all(16), children: [for (final m in list.reversed) _bubble(m)]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('netInput'),
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: NetworkMessage.maxLength,
                      decoration: InputDecoration(hintText: tr(context, 'typeMessage'), counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey('netSend'),
                    tooltip: tr(context, 'send'),
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

/// The load details inside a message.
class SharedLoadCardView extends StatelessWidget {
  final SharedLoad card;
  const SharedLoadCardView({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('sharedLoad_${card.loadId}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Flexible(child: Text('${card.pickup} → ${card.drop}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.title))),
          ]),
          const SizedBox(height: 4),
          Text('${card.cargoType} · ${formatNum(card.weight)} T · ${card.vehicleType}', style: TextStyle(fontSize: 12, color: AppColors.body)),
          if (card.budgetPaise != null) Text(formatPaise(card.budgetPaise!), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.title)),
        ],
      ),
    );
  }
}
