import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/fraud_case.dart';
import '../core/services/fraud_case_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

String caseStatusLabel(BuildContext context, String s) => tr(context, 'case_$s');

Color _statusColor(String s) => switch (s) {
      FraudCase.investigating => AppColors.warning,
      FraudCase.resolved => AppColors.success,
      FraudCase.dismissed => AppColors.faint,
      _ => AppColors.primary,
    };

/// Admin > Fraud cases: list, filter by status, open a case by hand.
class AdminFraudCasesScreen extends StatefulWidget {
  const AdminFraudCasesScreen({super.key});

  @override
  State<AdminFraudCasesScreen> createState() => _AdminFraudCasesScreenState();
}

class _AdminFraudCasesScreenState extends State<AdminFraudCasesScreen> {
  String? _filter;

  Future<void> _newCase() async {
    final user = TextEditingController();
    final summary = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'newCase')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const ValueKey('caseUser'), controller: user, decoration: InputDecoration(labelText: tr(context, 'userId')), inputFormatters: [LengthLimitingTextInputFormatter(128)]),
          TextField(key: const ValueKey('caseSummary'), controller: summary, maxLength: 300, decoration: InputDecoration(labelText: tr(context, 'caseSummary'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'cancel'))),
          FilledButton(key: const ValueKey('caseCreate'), onPressed: () => Navigator.pop(context, true), child: Text(tr(context, 'save'))),
        ],
      ),
    );
    final u = user.text, s = summary.text;
    if (ok != true || !mounted) return;
    try {
      final id = await FraudCaseService.open(userId: u, summary: s);
      if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => FraudCaseScreen(caseId: id)));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminFraudCases'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('newCase'),
        onPressed: _newCase,
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'newCase')),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(spacing: 8, children: [
            ChoiceChip(label: Text(tr(context, 'all')), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
            for (final s in FraudCase.statuses)
              ChoiceChip(key: ValueKey('filter_$s'), label: Text(caseStatusLabel(context, s)), selected: _filter == s, onSelected: (_) => setState(() => _filter = s)),
          ]),
        ),
        Expanded(
          child: LiveStream<List<FraudCase>>(
            stream: FraudCaseService.watchAll,
            builder: (context, all) {
              final list = [for (final c in all) if (_filter == null || c.status == _filter) c];
              if (list.isEmpty) return EmptyState(icon: Icons.gavel_rounded, title: tr(context, 'noCases'));
              return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 90), children: [
                for (final c in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      key: ValueKey('case_${c.id}'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FraudCaseScreen(caseId: c.id))),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.summary, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(c.userId, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          ]),
                        ),
                        StatusChip(label: caseStatusLabel(context, c.status), color: _statusColor(c.status)),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

/// One case: status, notes (append-only), and the closing decision.
class FraudCaseScreen extends StatefulWidget {
  final String caseId;
  const FraudCaseScreen({super.key, required this.caseId});

  @override
  State<FraudCaseScreen> createState() => _FraudCaseScreenState();
}

class _FraudCaseScreenState extends State<FraudCaseScreen> {
  final _note = TextEditingController();
  late final Stream<FraudCase?> _case = FraudCaseService.watch(widget.caseId).asBroadcastStream();
  late final Stream<List<CaseNote>> _notes = FraudCaseService.watchNotes(widget.caseId).asBroadcastStream();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Future<void> _addNote() async {
    final text = _note.text;
    if (text.trim().isEmpty) return;
    await _run(() => FraudCaseService.addNote(widget.caseId, text));
    _note.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'fraudCase'))),
      body: StreamBuilder<FraudCase?>(
        stream: _case,
        builder: (context, snap) {
          final c = snap.data;
          if (c == null) return const Center(child: CircularProgressIndicator());
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(c.summary, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${tr(context, 'userId')}: ${c.userId}', style: const TextStyle(color: AppColors.muted)),
            if (c.reportIds.isNotEmpty) Text(trf(context, 'caseReports', {'n': c.reportIds.length}), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 10),
            Row(children: [
              StatusChip(label: caseStatusLabel(context, c.status), color: _statusColor(c.status)),
              if (c.outcome != null) ...[const SizedBox(width: 8), StatusChip(label: tr(context, 'outcome_${c.outcome}'), color: AppColors.primary)],
            ]),
            if (!c.isClosed) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final s in const [FraudCase.open, FraudCase.investigating])
                  ChoiceChip(
                    key: ValueKey('setStatus_$s'),
                    label: Text(caseStatusLabel(context, s)),
                    selected: c.status == s,
                    onSelected: (_) => _run(() => FraudCaseService.setStatus(c.id, s)),
                  ),
              ]),
              const SizedBox(height: 16),
              Text(tr(context, 'caseDecision'), style: const TextStyle(fontWeight: FontWeight.w800)),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final o in FraudCase.outcomes)
                  OutlinedButton(
                    key: ValueKey('close_$o'),
                    onPressed: () => _run(() => FraudCaseService.close(c.id, userId: c.userId, outcome: o, dismiss: o == FraudCase.outcomeNoAction)),
                    child: Text(tr(context, 'outcome_$o')),
                  ),
              ]),
            ],
            const Divider(height: 32),
            Text(tr(context, 'caseNotes'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            StreamBuilder<List<CaseNote>>(
              stream: _notes,
              builder: (context, ns) => Column(children: [
                for (final n in ns.data ?? const <CaseNote>[])
                  ListTile(
                    key: ValueKey('note_${n.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(n.text),
                    subtitle: Text('${n.by}${n.createdAt == null ? '' : ' · ${formatDateTime(n.createdAt!)}'}'),
                  ),
              ]),
            ),
            Row(children: [
              Expanded(child: TextField(key: const ValueKey('noteField'), controller: _note, maxLength: 1000, decoration: InputDecoration(labelText: tr(context, 'addNote')))),
              IconButton(key: const ValueKey('noteAdd'), onPressed: _addNote, icon: const Icon(Icons.send_rounded)),
            ]),
          ]);
        },
      ),
    );
  }
}
