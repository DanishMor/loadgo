import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/chat_message.dart';
import '../core/services/comm_admin_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// One booking's chat, opened for a report or a dispute (and logged). Also
/// shows both phone numbers on request; that is logged too.
class AdminChatReviewScreen extends StatefulWidget {
  final String bookingId;

  /// The two people of the booking (customer first) as ids.
  final List<String> parties;

  const AdminChatReviewScreen({super.key, required this.bookingId, this.parties = const []});

  @override
  State<AdminChatReviewScreen> createState() => _AdminChatReviewScreenState();
}

class _AdminChatReviewScreenState extends State<AdminChatReviewScreen> {
  Map<String, String>? _phones;

  Future<void> _show() async {
    try {
      final phones = await CommAdminService.revealPhones(widget.parties, bookingId: widget.bookingId);
      if (mounted) setState(() => _phones = phones);
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'chat'))),
      body: Column(children: [
        if (widget.parties.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _phones == null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(key: const ValueKey('showBothNumbers'), onPressed: _show, icon: const Icon(Icons.visibility_outlined), label: Text(tr(context, 'pcShowNumbers'))),
                  )
                : AppCard(
                    key: const ValueKey('bothNumbers'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (var i = 0; i < widget.parties.length; i++)
                        Text('${tr(context, i == 0 ? 'pcCustomerLabel' : 'pcDriverLabel')}: ${_phones![widget.parties[i]] ?? ''}'),
                      Text(tr(context, 'pcNumbersLogged'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
                    ]),
                  ),
          ),
        Expanded(
          child: LiveStream<List<ChatMessage>>(
            stream: () => CommAdminService.watchChat(widget.bookingId),
            builder: (context, list) {
              if (list.isEmpty) return EmptyState(icon: Icons.chat_bubble_outline_rounded, title: tr(context, 'noMessages'));
              return ListView(padding: const EdgeInsets.all(16), children: [
                for (final m in list)
                  ListTile(
                    dense: true,
                    title: Text(m.text),
                    subtitle: Text('${m.senderId}${m.createdAt == null ? '' : ' · ${formatDateTime(m.createdAt!)}'}'),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
