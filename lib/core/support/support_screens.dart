import 'dart:async';

import 'package:flutter/material.dart';

import '../admin/reply_templates.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/support_ticket.dart';
import '../services/backend.dart';
import '../services/reply_template_service.dart';
import '../services/booking_service.dart';
import '../services/support_config.dart';
import '../services/support_service.dart';
import '../safety/call.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';

String ticketCategoryLabel(BuildContext context, String c) => tr(context, switch (c) {
  TicketCategory.bookingIssue => 'catBookingIssue',
  TicketCategory.payment => 'catPayment',
  TicketCategory.dispute => 'catDispute',
  TicketCategory.safety => 'catSafety',
  TicketCategory.account => 'catAccount',
  _ => 'catOther',
});

String ticketPriorityLabel(BuildContext context, String p) => tr(context, switch (p) {
  TicketPriority.low => 'prioLow',
  TicketPriority.high => 'prioHigh',
  TicketPriority.urgent => 'prioUrgent',
  _ => 'prioNormal',
});

String ticketStatusLabel(BuildContext context, String s) => tr(context, switch (s) {
  TicketStatus.inProgress => 'ticketInProgress',
  TicketStatus.resolved => 'ticketResolved',
  TicketStatus.closed => 'ticketClosed',
  _ => 'ticketOpen',
});

Color ticketStatusColor(String s) => switch (s) {
  TicketStatus.inProgress => AppColors.warning,
  TicketStatus.resolved => AppColors.success,
  TicketStatus.closed => AppColors.faint,
  _ => AppColors.primary,
};

/// One ticket row, reused by the admin queue.
class TicketTile extends StatelessWidget {
  final SupportTicket ticket;
  final VoidCallback onTap;
  const TicketTile({super.key, required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.subject,
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title),
                ),
              ),
              StatusChip(label: ticketStatusLabel(context, t.status), color: ticketStatusColor(t.status)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (t.businessId != null) tr(context, 'bizSupport'),
              ticketCategoryLabel(context, t.category),
              ticketPriorityLabel(context, t.priority),
              if (t.escalationLevel > 0) trf(context, 'escalationLevel', {'n': t.escalationLevel}),
              if (t.updatedAt != null) formatDateTime(t.updatedAt!),
            ].join(' • '),
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// The user's tickets plus a button to open a new one.
class SupportHomeScreen extends StatelessWidget {
  const SupportHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'helpSupport'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('newTicket'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewTicketScreen())),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'newTicket')),
      ),
      body: SafeArea(
        child: Column(children: [
          FutureBuilder<SupportConfig>(
            future: SupportConfig.load(),
            builder: (context, snap) {
              final c = snap.data;
              if (c == null || !c.hasPhone) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: AppCard(
                  key: const ValueKey('callSupport'),
                  onTap: () => callNumber(context, c.phone),
                  child: Row(children: [
                    const Icon(Icons.call_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr(context, 'callSupport'), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(c.hours.isEmpty ? c.phone : '${c.phone} · ${c.hours}', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          ),
          Expanded(child: LiveStream<List<SupportTicket>>(
          stream: SupportService.watchMine,
          builder: (context, tickets) {
            if (tickets.isEmpty) return EmptyState(icon: Icons.support_agent_rounded, title: tr(context, 'noTickets'));
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
              itemCount: tickets.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => TicketTile(
                ticket: tickets[i],
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => TicketDetailScreen(ticketId: tickets[i].id))),
              ),
            );
          },
        )),
        ]),
      ),
    );
  }
}

/// Form for a new ticket; [bookingId]/[category] preselect when opened from a booking.
class NewTicketScreen extends StatefulWidget {
  final String? bookingId;
  final String? category;

  /// A company ticket (BIZ15): the owner's uid.
  final String? businessId;
  const NewTicketScreen({super.key, this.bookingId, this.category, this.businessId});

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _desc = TextEditingController();
  late String _category = widget.category ?? TicketCategory.bookingIssue;
  String _priority = TicketPriority.normal;
  late String? _bookingId = widget.bookingId;
  List<Booking> _bookings = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    try {
      final lists = await Future.wait([BookingService.watchForDriver().first, BookingService.watchForCustomer().first]);
      if (mounted) setState(() => _bookings = [...lists[0], ...lists[1]]);
    } catch (_) {
      // Linking a booking is optional.
    }
  }

  @override
  void dispose() {
    _subject.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await SupportService.create(
        category: _category,
        subject: _subject.text,
        description: _desc.text,
        priority: _priority,
        bookingId: _bookingId,
        businessId: widget.businessId,
      );
      if (!mounted) return;
      showSnack(context, tr(context, 'ticketCreated'));
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    // A booking passed in may not be in the loaded list (yet); keep it selectable.
    final bookingIds = <String, Booking?>{for (final b in _bookings) b.id: b};
    if (_bookingId != null) bookingIds.putIfAbsent(_bookingId!, () => null);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'newTicket'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          // Not lazy: a Form only validates fields that are built.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldLabel(tr(context, 'ticketCategory')),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: const ValueKey('ticketCategory'),
                  initialValue: _category,
                  items: [
                    for (final c in TicketCategory.all)
                      DropdownMenuItem(value: c, child: Text(ticketCategoryLabel(context, c))),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
                const SizedBox(height: 14),
                FieldLabel(tr(context, 'priority')),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _priority,
                  items: [
                    for (final p in TicketPriority.all)
                      DropdownMenuItem(value: p, child: Text(ticketPriorityLabel(context, p))),
                  ],
                  onChanged: (v) => setState(() => _priority = v ?? _priority),
                ),
                const SizedBox(height: 14),
                FieldLabel(tr(context, 'relatedBooking')),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('ticketBooking'),
                  initialValue: _bookingId,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(tr(context, 'noBookingLink'))),
                    for (final e in bookingIds.entries)
                      DropdownMenuItem<String?>(
                        value: e.key,
                        child: Text(
                          e.value == null ? e.key : '${e.value!.pickup} → ${e.value!.drop}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _bookingId = v),
                  validator: (v) =>
                      _category == TicketCategory.dispute && v == null ? tr(context, 'disputeNeedsBooking') : null,
                ),
                const SizedBox(height: 14),
                FieldLabel(tr(context, 'subject')),
                TextFormField(
                  key: const ValueKey('ticketSubject'),
                  controller: _subject,
                  maxLength: 100,
                  decoration: const InputDecoration(counterText: ''),
                  validator: (v) => (v == null || v.trim().length < 3) ? tr(context, 'fieldRequired') : null,
                ),
                const SizedBox(height: 14),
                FieldLabel(tr(context, 'describeIssue')),
                TextFormField(controller: _desc, maxLength: 1000, maxLines: 5),
                const SizedBox(height: 20),
                PrimaryButton(label: tr(context, 'newTicket'), loading: _saving, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ticket thread: details, replies, reply box, escalate and close.
/// [asAdmin] switches replies to the support side (admin screens).
class TicketDetailScreen extends StatefulWidget {
  final String ticketId;
  final bool asAdmin;
  final Widget? adminControls;
  const TicketDetailScreen({super.key, required this.ticketId, this.asAdmin = false, this.adminControls});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  final _reply = TextEditingController();
  late final Stream<SupportTicket?> _ticket = SupportService.watch(widget.ticketId);
  late final Stream<List<TicketReply>> _replies = SupportService.watchReplies(widget.ticketId);
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  /// Support side: choose a canned answer; it is put into the reply box to be
  /// edited before sending.
  Future<void> _pickTemplate() async {
    final templates = await ReplyTemplateService.load();
    if (!mounted) return;
    final picked = await showModalBottomSheet<ReplyTemplate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: templates.isEmpty
            ? Padding(padding: const EdgeInsets.all(24), child: Text(tr(c, 'tplNone')))
            : ListView(shrinkWrap: true, children: [
                for (final t in templates)
                  ListTile(
                    key: ValueKey('pickTpl_${t.id}'),
                    title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(t.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(c, t),
                  ),
              ]),
      ),
    );
    if (picked == null) return;
    final current = _reply.text.trim();
    final text = current.isEmpty ? picked.text : '$current\n${picked.text}';
    _reply.text = text.length > 1000 ? text.substring(0, 1000) : text;
    _reply.selection = TextSelection.collapsed(offset: _reply.text.length);
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) showSnack(context, tr(context, done));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'helpSupport'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: LiveDoc<SupportTicket>(
          stream: () => _ticket,
          builder: (context, t) {
            if (t == null) return EmptyState(icon: Icons.search_off_rounded, title: tr(context, 'noTickets'));
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    children: [
                      TicketTile(ticket: t, onTap: () {}),
                      if (t.description.isNotEmpty)
                        Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(t.description)),
                      ?widget.adminControls,
                      if (!widget.asAdmin && t.isOpen)
                        Wrap(
                          spacing: 8,
                          children: [
                            if (t.canEscalate)
                              OutlinedButton.icon(
                                key: const ValueKey('escalate'),
                                onPressed: _busy
                                    ? null
                                    : () => _run(() => SupportService.escalate(t), done: 'escalated'),
                                icon: const Icon(Icons.trending_up_rounded),
                                label: Text(tr(context, 'escalate')),
                              ),
                            TextButton(
                              key: const ValueKey('closeTicket'),
                              onPressed: _busy ? null : () => _run(() => SupportService.close(t.id)),
                              child: Text(tr(context, 'closeTicket')),
                            ),
                          ],
                        ),
                      const Divider(height: 24),
                      StreamBuilder<List<TicketReply>>(
                        stream: _replies,
                        builder: (context, rs) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final r in rs.data ?? const <TicketReply>[])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.fromAdmin
                                          ? tr(context, 'supportTeam')
                                          : (r.authorId == Backend.uid ? tr(context, 'you') : tr(context, 'customer')),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: r.fromAdmin ? AppColors.primary : AppColors.title,
                                      ),
                                    ),
                                    Text(r.text),
                                    if (r.createdAt != null)
                                      Text(
                                        formatDateTime(r.createdAt!),
                                        style: TextStyle(fontSize: 11, color: AppColors.faint),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (t.status != TicketStatus.closed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        if (widget.asAdmin)
                          IconButton(
                            key: const ValueKey('replyTemplates'),
                            tooltip: tr(context, 'tplPick'),
                            onPressed: _busy ? null : _pickTemplate,
                            icon: const Icon(Icons.quickreply_outlined),
                          ),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('replyInput'),
                            controller: _reply,
                            maxLength: 1000,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(hintText: tr(context, 'replyHint'), counterText: ''),
                          ),
                        ),
                        IconButton.filled(
                          key: const ValueKey('replySend'),
                          onPressed: _busy
                              ? null
                              : () {
                                  final text = _reply.text;
                                  if (text.trim().isEmpty) return;
                                  unawaited(
                                    _run(() async {
                                      await SupportService.reply(t.id, text, asAdmin: widget.asAdmin);
                                      _reply.clear();
                                    }),
                                  );
                                },
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
