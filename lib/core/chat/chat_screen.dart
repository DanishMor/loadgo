import 'package:flutter/material.dart';
import '../widgets/live_stream.dart';
import '../services/rate_limit_service.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/chat_message.dart';
import '../services/backend.dart';
import '../services/chat_service.dart';
import '../widgets/common.dart';
import '../call/call_models.dart';
import '../call/call_screens.dart';
import '../comm/chat_strikes.dart';
import '../services/comm_guard.dart';
import '../services/server_clock.dart';

/// "Chat" button with an unread badge for a booking (both roles).
class BookingChatButton extends StatelessWidget {
  final Booking booking;
  const BookingChatButton({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: ChatService.watchUnread(booking.id),
      builder: (context, snap) {
        final unread = snap.data ?? 0;
        return OutlinedButton.icon(
          key: const ValueKey('openChat'),
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(booking: booking))),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.chat_bubble_outline_rounded),
          ),
          label: Text(tr(context, 'chat')),
        );
      },
    );
  }
}

/// Customer–driver chat for one booking, with off-platform warnings,
/// report and block.
class ChatScreen extends StatefulWidget {
  final Booking booking;
  const ChatScreen({super.key, required this.booking});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  late final Stream<List<ChatMessage>> _messages = ChatService.watch(widget.booking.id);
  late final String _other = ChatService.otherParty(widget.booking);
  late final Stream<bool> _blocked = ChatService.watchBlocked(_other);
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    ChatService.markRead(widget.booking.id).catchError((_) {});
    CommGuard.decayIfDue();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    if (text.length > ChatMessage.maxLength) {
      showSnack(context, tr(context, 'messageTooLong'));
      return;
    }
    setState(() => _sending = true);
    try {
      await ChatService.send(widget.booking, text);
      _ctrl.clear();
    } on ChatContactException catch (e) {
      // Nothing was sent. The text stays in the box so it can be edited.
      if (mounted) await _showContactWarning(e.outcome);
    } on ChatBlockedException catch (e) {
      if (mounted) showSnack(context, trf(context, 'pcBlockedBanner', {'until': formatDateTime(e.until)}));
    } on RateLimitException catch (e) {
      if (mounted) showSnack(context, trf(context, 'rateLimited', {'m': e.minutesLeft}));
    } on ChatSendException catch (e) {
      if (mounted) showSnack(context, tr(context, switch (e.reason) { 'blocked' => 'cannotSendBlocked', 'repeat' => 'chatRepeat', _ => 'somethingWrong' }));
    } catch (_) {
      if (mounted) showRetrySnack(context, tr(context, 'somethingWrong'), _send);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    ChatService.markRead(widget.booking.id).catchError((_) {});
  }

  Future<void> _showContactWarning(ViolationOutcome o) {
    final until = o.blockedUntil;
    final body = until == null
        ? trf(context, 'pcWarnBody', {'n': o.strikes.clamp(1, ChatLadder.warnings)})
        : trf(context, 'pcBlockBody', {'until': formatDateTime(until), 'n': o.strikes});
    return showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        key: const ValueKey('contactWarning'),
        icon: const Icon(Icons.shield_outlined),
        title: Text(tr(c, 'pcWarnTitle')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(c, 'pcKind${o.kind.name}'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body),
          if (o.review) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr(c, 'pcReviewNote'))),
          if (!o.recorded) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr(c, 'pcNotRecorded'), style: TextStyle(color: AppColors.muted, fontSize: 12))),
        ]),
        actions: [FilledButton(key: const ValueKey('contactWarningOk'), onPressed: () => Navigator.of(c).pop(), child: Text(tr(c, 'pcOk')))],
      ),
    );
  }

  Future<void> _report({String? messageId}) async {
    final result = await showDialog<(String, String)>(context: context, builder: (_) => const _ReportDialog());
    if (result == null || !mounted) return;
    try {
      await ChatService.report(widget.booking, reason: result.$1, details: result.$2, messageId: messageId);
      if (mounted) showSnack(context, tr(context, 'reportSent'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.senderId == Backend.uid;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: mine ? null : () => _report(messageId: m.id),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
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
              Text(m.text, style: TextStyle(color: mine ? Colors.white : AppColors.title)),
              if (m.flagged)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: mine ? Colors.white70 : AppColors.warning),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(tr(context, 'flaggedMessage'),
                            style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : AppColors.warning)),
                      ),
                    ],
                  ),
                ),
              if (m.createdAt != null)
                Text(formatDateTime(m.createdAt!),
                    style: TextStyle(fontSize: 10, color: mine ? Colors.white60 : AppColors.faint)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'chat'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (bookingAllowsCall(widget.booking))
            IconButton(
              key: const ValueKey('chatCall'),
              tooltip: tr(context, 'pcCall'),
              icon: const Icon(Icons.call_rounded),
              onPressed: () => startBookingCall(context, widget.booking),
            ),
          StreamBuilder<bool>(
            stream: _blocked,
            builder: (context, snap) {
              final blocked = snap.data ?? false;
              return PopupMenuButton<String>(
                key: const ValueKey('chatMenu'),
                onSelected: (v) async {
                  if (v == 'report') await _report();
                  if (v == 'block') await ChatService.block(_other);
                  if (v == 'unblock') await ChatService.unblock(_other);
                },
                itemBuilder: (c) => [
                  PopupMenuItem(value: 'report', child: Text(tr(c, 'reportUser'))),
                  PopupMenuItem(value: blocked ? 'unblock' : 'block', child: Text(tr(c, blocked ? 'unblockUser' : 'blockUser'))),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.warnBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(tr(context, 'pcChatNote'), style: TextStyle(fontSize: 12, color: AppColors.body)),
            ),
            StreamBuilder<ChatStatus>(
              stream: CommGuard.watch(),
              builder: (context, snap) {
                final until = snap.data?.blockedUntil;
                if (until == null || !until.isAfter(ServerClock.now())) return const SizedBox.shrink();
                return Container(
                  key: const ValueKey('chatBlockedBanner'),
                  width: double.infinity,
                  color: Colors.red.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(trf(context, 'pcBlockedBanner', {'until': formatDateTime(until)}), style: TextStyle(fontSize: 12, color: AppColors.body)),
                );
              },
            ),
            Expanded(
              child: LiveStream<List<ChatMessage>>(
                stream: () => _messages,
                builder: (context, list) {
                  if (list.isEmpty) {
                    return EmptyState(icon: Icons.chat_bubble_outline_rounded, title: tr(context, 'noMessages'));
                  }
                  return ListView(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    children: [for (final m in list.reversed) _bubble(m)],
                  );
                },
              ),
            ),
            StreamBuilder<bool>(
              stream: _blocked,
              builder: (context, snap) {
                if (snap.data == true) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(tr(context, 'youBlocked'), style: TextStyle(color: AppColors.muted)),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chatInput'),
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: ChatMessage.maxLength,
                          decoration: InputDecoration(hintText: tr(context, 'typeMessage'), counterText: ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        key: const ValueKey('chatSend'),
                        tooltip: tr(context, 'send'),
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String _reason = ReportReason.abuse;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  static String _label(String r) => switch (r) {
        ReportReason.fraud => 'reasonFraud',
        ReportReason.offPlatform => 'reasonOffPlatform',
        ReportReason.askedNumber => 'reasonAskedNumber',
        ReportReason.sentNumber => 'reasonSentNumber',
        ReportReason.other => 'reasonOther',
        _ => 'reasonAbuse',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'reportReasonTitle')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v ?? _reason),
              child: Column(
                children: [
                  for (final r in ReportReason.all)
                    RadioListTile<String>(contentPadding: EdgeInsets.zero, value: r, title: Text(tr(context, _label(r)))),
                ],
              ),
            ),
            TextField(
              controller: _details,
              maxLength: 300,
              maxLines: 2,
              decoration: InputDecoration(labelText: tr(context, 'reportDetails'), counterText: ''),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr(context, 'cancel'))),
        FilledButton(
          key: const ValueKey('reportSubmit'),
          onPressed: () => Navigator.of(context).pop((_reason, _details.text)),
          child: Text(tr(context, 'reportUser')),
        ),
      ],
    );
  }
}
