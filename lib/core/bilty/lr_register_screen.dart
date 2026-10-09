import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/backend.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import 'lr_copy_screen.dart';
import 'lr_model.dart';
import 'lr_register.dart';
import 'lr_service.dart';

/// All the LRs a person issued: search, status filter, and the state of every
/// share link (active, expired, revoked) with a way to stop one
/// (MASTER-6 Task 31).
class LrRegisterScreen extends StatefulWidget {
  /// Test hooks.
  final Stream<List<LrPublic>>? lrs;
  final Stream<List<LrShare>>? shares;
  final DateTime Function() now;
  final Future<void> Function(LrShare, LrPublic)? revoke;
  final Future<Booking?> Function(String bookingId)? loadBooking;
  const LrRegisterScreen({super.key, this.lrs, this.shares, this.now = DateTime.now, this.revoke, this.loadBooking});

  @override
  State<LrRegisterScreen> createState() => _LrRegisterScreenState();
}

class _LrRegisterScreenState extends State<LrRegisterScreen> {
  late final Stream<List<LrPublic>> _lrs = (widget.lrs ?? LrService.watchMine()).asBroadcastStream();
  late final Stream<List<LrShare>> _shares = (widget.shares ?? LrService.watchMyShares()).asBroadcastStream();
  final _query = TextEditingController();
  String? _status;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String _statusKey(String s) => switch (s) { LrStatus.cancelled => 'blCancelled', LrStatus.superseded => 'blStatusSuperseded', _ => 'blStatusIssued' };

  Color _statusColor(String s) => switch (s) { LrStatus.cancelled => Colors.redAccent, LrStatus.superseded => AppColors.faint, _ => AppColors.success };

  Future<void> _open(LrRow r) async {
    final b = await (widget.loadBooking ?? _booking)(r.lr.bookingId);
    if (b == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LrCopyScreen(booking: b, lr: r.lr, copy: LrCopy.full)));
  }

  static Future<Booking?> _booking(String id) async {
    final d = await Backend.db.collection('bookings').doc(id).get();
    return d.exists ? Booking.fromDoc(d) : null;
  }

  Future<void> _links(LrRow r) async {
    final now = widget.now();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.lr.lrNo} · ${tr(c, _statusKey(r.lr.status))}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(r.lr.route.isEmpty ? '${r.lr.pickup} → ${r.lr.drop}' : r.lr.route, style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              OutlinedButton.icon(key: const ValueKey('lrOpenCopy'), onPressed: () => _open(r), icon: const Icon(Icons.description_outlined), label: Text(tr(c, 'lrrOpen'))),
              const SizedBox(height: 12),
              Text(tr(c, 'lrrLinks'), style: const TextStyle(fontWeight: FontWeight.w800)),
              if (r.shares.isEmpty) Text(tr(c, 'lrrNoLinks'), key: const ValueKey('lrrNoLinks'), style: TextStyle(color: AppColors.muted)),
              for (final s in r.shares.where((s) => s.copyType != 'verify'))
                ListTile(
                  key: ValueKey('lrLink_${s.token}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${tr(c, 'lrrCopy_${s.copyType}')} · …${s.token.substring(s.token.length > 6 ? s.token.length - 6 : 0)}'),
                  subtitle: Text('${tr(c, 'lrrState_${LrRegister.stateOf(s, now).name}')}${s.expiresAt == null ? '' : ' · ${formatDateTime(s.expiresAt!)}'} · ${trf(c, 'lrrViews', {'n': s.views})}'),
                  trailing: LrRegister.stateOf(s, now) == LinkState.active
                      ? TextButton(
                          key: ValueKey('lrRevoke_${s.token}'),
                          onPressed: () async {
                            final nav = Navigator.of(c);
                            await (widget.revoke ?? LrService.revokeShare)(s, r.lr);
                            nav.pop();
                          },
                          child: Text(tr(c, 'lrrStop')),
                        )
                      : null,
                ),
            ]),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, scrolledUnderElevation: 0, title: Text(tr(context, 'lrrTitle'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: LiveStream<List<LrPublic>>(
          stream: () => _lrs,
          builder: (context, all) => LiveStream<List<LrShare>>(
            stream: () => _shares,
            compact: true,
            builder: (context, shares) {
              if (all.isEmpty) return EmptyState(icon: Icons.description_outlined, title: tr(context, 'lrrNone'));
              final now = widget.now();
              final rows = LrRegister.rows(all, shares);
              final counts = LrRegister.counts(rows);
              final shown = LrRegister.filter(rows, query: _query.text, status: _status);
              return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 30), children: [
                TextField(
                  key: const ValueKey('lrrSearch'),
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr(context, 'lrrSearchHint')),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: [
                  ChoiceChip(key: const ValueKey('lrrAll'), label: Text('${tr(context, 'lrrAll')} (${counts[null]})'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                  for (final s in const [LrStatus.issued, LrStatus.cancelled, LrStatus.superseded])
                    if ((counts[s] ?? 0) > 0) ChoiceChip(key: ValueKey('lrrStatus_$s'), label: Text('${tr(context, _statusKey(s))} (${counts[s]})'), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                ]),
                const SizedBox(height: 8),
                if (shown.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr(context, 'lrrNoMatch'), key: const ValueKey('lrrNoMatch'), textAlign: TextAlign.center)),
                for (final r in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      key: ValueKey('lrRow_${r.lr.lrNo}'),
                      onTap: () => _links(r),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(r.lr.lrNo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                          StatusChip(label: tr(context, _statusKey(r.lr.status)), color: _statusColor(r.lr.status)),
                        ]),
                        Text(r.lr.route.isEmpty ? '${r.lr.pickup} → ${r.lr.drop}' : r.lr.route, style: TextStyle(color: AppColors.muted)),
                        if (r.lr.date != null || r.lr.goods.isNotEmpty) Text([if (r.lr.date != null) formatDate(r.lr.date!), if (r.lr.goods.isNotEmpty) r.lr.goods].join(' · '), style: TextStyle(color: AppColors.faint, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(trf(context, 'lrrLinkCounts', {'a': r.active(now), 'e': r.expired(now), 'r': r.revoked()}), key: ValueKey('lrLinks_${r.lr.lrNo}'), style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
