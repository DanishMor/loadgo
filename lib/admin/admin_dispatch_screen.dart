import 'package:flutter/material.dart';

import '../core/admin/dispatch.dart';
import '../core/errors/friendly_error.dart';
import '../core/l10n/l10n.dart';
import '../core/models/load.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Manual dispatch (MASTER-6 Task 4): loads that wait for a driver,
/// the nearest fitting drivers, a suggestion with a note, and a call-back note
/// about the customer. Nothing is assigned: the driver accepts as usual.
class AdminDispatchScreen extends StatefulWidget {
  /// Test hooks; default to the live reads and writes.
  final Future<List<Load>> Function()? loadLoads;
  final Future<List<({DispatchCandidate c, String name})>> Function(Load)? candidates;
  final Future<void> Function(Load, String driverId, String note)? suggest;
  final Future<void> Function(Load, String text)? callback;
  const AdminDispatchScreen({super.key, this.loadLoads, this.candidates, this.suggest, this.callback});

  @override
  State<AdminDispatchScreen> createState() => _AdminDispatchScreenState();
}

class _AdminDispatchScreenState extends State<AdminDispatchScreen> {
  late Future<List<Load>> _data = (widget.loadLoads ?? AdminConsoleService.unfilledLoads)();

  void _refresh() {
    final next = (widget.loadLoads ?? AdminConsoleService.unfilledLoads)();
    setState(() {
      _data = next;
    });
  }

  void _say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _suggest(Load load) async {
    final list = await (widget.candidates ?? AdminConsoleService.dispatchCandidates)(load);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SuggestSheet(
        load: load,
        candidates: list,
        onSend: (driverId, note) async {
          try {
            await (widget.suggest ?? ((l, d, n) => AdminConsoleService.suggestLoad(l, d, note: n)))(load, driverId, note);
            if (mounted) _say(tr(context, 'dispSent'));
          } catch (e) {
            if (mounted) _say(tr(context, FriendlyError.of(e)));
          }
        },
      ),
    );
  }

  Future<void> _callback(Load load) async {
    final t = await showDialog<String>(context: context, builder: (ctx) => const _CallbackDialog());
    if (t == null || t.isEmpty) return;
    try {
      await (widget.callback ?? AdminConsoleService.callbackNote)(load, t);
    } catch (e) {
      if (mounted) _say(tr(context, FriendlyError.of(e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminDispatch')), actions: [IconButton(key: const ValueKey('dispRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<Load>>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final loads = snap.data;
          if (loads == null) return const Center(child: CircularProgressIndicator());
          if (loads.isEmpty) return EmptyState(icon: Icons.task_alt_rounded, title: tr(context, 'dispNone'));
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final l in loads)
              AppCard(
                key: ValueKey('dispLoad_${l.id}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${l.pickup} → ${l.drop}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${l.weight} t · ${l.vehicleType}', style: TextStyle(color: AppColors.muted)),
                  Wrap(spacing: 8, children: [
                    FilledButton.tonal(key: ValueKey('dispSuggest_${l.id}'), onPressed: () => _suggest(l), child: Text(tr(context, 'dispSuggest'))),
                    OutlinedButton(key: ValueKey('dispCall_${l.id}'), onPressed: () => _callback(l), child: Text(tr(context, 'dispCallback'))),
                  ]),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class _SuggestSheet extends StatefulWidget {
  final Load load;
  final List<({DispatchCandidate c, String name})> candidates;
  final Future<void> Function(String driverId, String note) onSend;
  const _SuggestSheet({required this.load, required this.candidates, required this.onSend});

  @override
  State<_SuggestSheet> createState() => _SuggestSheetState();
}

class _SuggestSheetState extends State<_SuggestSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.candidates;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${widget.load.pickup} → ${widget.load.drop}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (list.isEmpty) Text(tr(context, 'dispNoDrivers'), key: const ValueKey('dispNoDrivers')),
          TextField(key: const ValueKey('dispNote'), controller: _note, maxLength: Dispatch.maxNote, decoration: InputDecoration(labelText: tr(context, 'dispNoteHint'))),
          for (final x in list)
            ListTile(
              key: ValueKey('dispCand_${x.c.driverId}'),
              contentPadding: EdgeInsets.zero,
              title: Text('${x.name.isEmpty ? x.c.driverId : x.name} · ${x.c.vehicleNumber}'),
              subtitle: Text(x.c.km == null ? tr(context, 'dispKmUnknown') : trf(context, 'dispKm', {'km': x.c.km!.round()})),
              trailing: FilledButton(
                key: ValueKey('dispSend_${x.c.driverId}'),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  await widget.onSend(x.c.driverId, _note.text);
                  nav.pop();
                },
                child: Text(tr(context, 'dispSend')),
              ),
            ),
        ]),
      ),
    );
  }
}

class _CallbackDialog extends StatefulWidget {
  const _CallbackDialog();

  @override
  State<_CallbackDialog> createState() => _CallbackDialogState();
}

class _CallbackDialogState extends State<_CallbackDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'dispCallback')),
      content: TextField(key: const ValueKey('dispCallbackText'), controller: _text, maxLength: 800, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
        FilledButton(key: const ValueKey('dispCallbackSave'), onPressed: () => Navigator.pop(context, _text.text.trim()), child: Text(tr(context, 'save'))),
      ],
    );
  }
}
