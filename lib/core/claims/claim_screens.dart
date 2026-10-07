import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import 'declared_value_line.dart';
import '../models/booking.dart';
import '../models/claim.dart';
import '../services/backend.dart';
import '../services/claim_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';

String claimStatusLabel(BuildContext context, Claim c) => c.isClosed && c.outcome != null
    ? '${tr(context, 'dspStatus_resolved')}: ${tr(context, 'dspOutcome_${c.outcome}')}'
    : tr(context, 'dspStatus_${c.status}');

/// On a booking screen (customer or driver): the claims of this booking and a
/// button to report a problem once the trip reached unloading.
class ClaimCard extends StatelessWidget {
  final Booking booking;

  const ClaimCard({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    return LiveStream<List<Claim>>(
      stream: () => ClaimService.watchForBooking(booking.id),
      compact: true,
      builder: (context, claims) {
        final uid = Backend.uid;
        final mine = claims.any((c) => c.openedBy == uid);
        if (claims.isEmpty && !ClaimService.canOpen(booking)) return const SizedBox.shrink();
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'dspTitle'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.title)),
            for (final c in claims)
              ListTile(
                key: ValueKey('claim_${c.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'dspType_${c.type}')),
                subtitle: Text(claimStatusLabel(context, c)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClaimScreen(claimId: c.id))),
              ),
            if (!mine && ClaimService.canOpen(booking))
              OutlinedButton.icon(
                key: const ValueKey('reportProblem'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewClaimScreen(booking: booking))),
                icon: const Icon(Icons.report_problem_outlined),
                label: Text(tr(context, 'reportProblem')),
              ),
          ]),
        );
      },
    );
  }
}

class NewClaimScreen extends StatefulWidget {
  final Booking booking;

  const NewClaimScreen({super.key, required this.booking});

  @override
  State<NewClaimScreen> createState() => _NewClaimScreenState();
}

class _NewClaimScreenState extends State<NewClaimScreen> {
  final _text = TextEditingController();
  final _amount = TextEditingController();
  String _type = ClaimType.damage;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rupees = int.tryParse(_amount.text.trim());
    setState(() => _busy = true);
    try {
      await ClaimService.open(
        booking: widget.booking,
        type: _type,
        description: _text.text,
        amountPaise: rupees == null ? null : rupees * 100,
      );
      if (!mounted) return;
      showSnack(context, tr(context, 'dspOpened'));
      Navigator.of(context).pop();
    } on ClaimException catch (e) {
      if (mounted) {
        showSnack(context, e.reason == 'already' ? tr(context, 'dspAlready') : tr(context, 'dspDescribe'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'reportProblem'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr(context, 'dspNote'), style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 14),
        FieldLabel(tr(context, 'dspType')),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: const ValueKey('claimType'),
          initialValue: _type,
          items: [for (final t in ClaimType.all) DropdownMenuItem(value: t, child: Text(tr(context, 'dspType_$t')))],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
        const SizedBox(height: 14),
        DeclaredValueLine(loadId: widget.booking.loadId),
        TextField(
          key: const ValueKey('claimText'),
          controller: _text,
          maxLength: 1000,
          maxLines: 4,
          decoration: InputDecoration(labelText: tr(context, 'dspDescribe')),
        ),
        TextField(
          key: const ValueKey('claimAmount'),
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          decoration: InputDecoration(labelText: tr(context, 'dspAmountOptional')),
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: tr(context, 'reportProblem'), loading: _busy, onPressed: _submit),
      ]),
    );
  }
}

/// One claim: details, timeline and a message box; admins also get review and
/// resolve controls.
class ClaimScreen extends StatefulWidget {
  final String claimId;
  final bool admin;

  const ClaimScreen({super.key, required this.claimId, this.admin = false});

  @override
  State<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends State<ClaimScreen> {
  final _msg = TextEditingController();
  late final Stream<Claim?> _claim = ClaimService.watch(widget.claimId).asBroadcastStream();
  late final Stream<List<ClaimEvent>> _events = ClaimService.watchEvents(widget.claimId).asBroadcastStream();

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _send(Claim c) async {
    final t = _msg.text;
    if (t.trim().isEmpty) return;
    _msg.clear();
    await ClaimService.addMessage(c, t, admin: widget.admin);
  }

  Future<void> _resolve(Claim c) async {
    final note = TextEditingController();
    final awarded = TextEditingController();
    var outcome = ClaimOutcome.upheld;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(tr(context, 'dspResolve')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(
              key: const ValueKey('claimOutcome'),
              value: outcome,
              isExpanded: true,
              items: [for (final o in ClaimOutcome.all) DropdownMenuItem(value: o, child: Text(tr(context, 'dspOutcome_$o')))],
              onChanged: (v) => set(() => outcome = v ?? outcome),
            ),
            TextField(key: const ValueKey('claimNote'), controller: note, maxLength: 1000, decoration: InputDecoration(labelText: tr(context, 'dspDecisionNote'))),
            TextField(
              key: const ValueKey('claimAwarded'),
              controller: awarded,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: InputDecoration(labelText: tr(context, 'dspAwarded')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'cancel'))),
            FilledButton(key: const ValueKey('claimResolveOk'), onPressed: () => Navigator.pop(context, true), child: Text(tr(context, 'dspResolve'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final rupees = int.tryParse(awarded.text.trim());
    await ClaimService.resolve(c, outcome: outcome, note: note.text, awardedPaise: rupees == null ? null : rupees * 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'dspTitle'))),
      body: LiveStream<Claim?>(
        stream: () => _claim,
        builder: (context, c) {
          if (c == null) return EmptyState(icon: Icons.report_problem_outlined, title: tr(context, 'dspNone'));
          return ListView(padding: const EdgeInsets.all(20), children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'dspType_${c.type}'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(claimStatusLabel(context, c), key: const ValueKey('claimStatus'), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                const SizedBox(height: 8),
                Text(c.description),
                DeclaredValueLine(bookingId: c.bookingId),
                if (c.amountPaise != null) Text(trf(context, 'dspClaimed', {'amount': formatPaise(c.amountPaise!)})),
                if (c.awardedPaise != null) Text(trf(context, 'dspAwardedLine', {'amount': formatPaise(c.awardedPaise!)})),
                if (c.resolutionNote.isNotEmpty) Text(c.resolutionNote, style: TextStyle(color: AppColors.muted)),
              ]),
            ),
            if (widget.admin && !c.isClosed)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(spacing: 8, children: [
                  if (c.status == ClaimStatus.open)
                    OutlinedButton(key: const ValueKey('claimStartReview'), onPressed: () => ClaimService.startReview(c), child: Text(tr(context, 'dspStartReview'))),
                  FilledButton(key: const ValueKey('claimResolve'), onPressed: () => _resolve(c), child: Text(tr(context, 'dspResolve'))),
                ]),
              ),
            const SizedBox(height: 16),
            Text(tr(context, 'dspTimeline'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            LiveStream<List<ClaimEvent>>(
              stream: () => _events,
              compact: true,
              builder: (context, events) => Column(children: [
                for (final e in events)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(e.kind == 'status' ? tr(context, 'dspStatus_${e.text}') : e.text),
                    subtitle: Text('${tr(context, 'dspRole_${e.role}')}${e.createdAt == null ? '' : ' · ${e.createdAt!.toLocal().toString().substring(0, 16)}'}'),
                  ),
              ]),
            ),
            if (widget.admin || !c.isClosed)
              Row(children: [
                Expanded(child: TextField(key: const ValueKey('claimMessage'), controller: _msg, maxLength: 1000, decoration: InputDecoration(hintText: tr(context, 'dspMessageHint'), counterText: ''))),
                IconButton(key: const ValueKey('claimSendBtn'), tooltip: tr(context, 'dspSend'), icon: const Icon(Icons.send_rounded), onPressed: () => _send(c)),
              ]),
          ]);
        },
      ),
    );
  }
}
