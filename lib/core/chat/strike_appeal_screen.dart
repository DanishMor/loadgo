import '../errors/error_text.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/server_clock.dart';
import '../services/strike_appeal_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';

/// A person's own strikes and a way to appeal one (MASTER-6 Task 34).
class StrikeAppealScreen extends StatefulWidget {
  /// Test hooks.
  final Future<List<MyStrike>> Function()? load;
  final Future<void> Function(MyStrike, String)? send;
  const StrikeAppealScreen({super.key, this.load, this.send});

  @override
  State<StrikeAppealScreen> createState() => _StrikeAppealScreenState();
}

class _StrikeAppealScreenState extends State<StrikeAppealScreen> {
  late Future<List<MyStrike>> _data = (widget.load ?? StrikeAppealService.mine)();

  void _refresh() {
    final next = (widget.load ?? StrikeAppealService.mine)();
    setState(() {
      _data = next;
    });
  }

  Future<void> _appeal(MyStrike s) async {
    final text = await showDialog<String>(context: context, builder: (_) => const _AppealDialog());
    if (text == null || !mounted) return;
    try {
      await (widget.send ?? ((st, t) => StrikeAppealService.appeal(st, t)))(s, text);
      if (mounted) showSnack(context, tr(context, 'apSent'));
      _refresh();
    } on AppealException catch (e) {
      if (mounted) showSnack(context, tr(context, switch (e.reason) { 'text' => 'apTextShort', 'closed' => 'apClosed', _ => 'apExists' }));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  String _kind(String k) => switch (k) {
        'phone' => 'pcKindphone',
        'upi' => 'pcKindupi',
        'app' => 'pcKindapp',
        'payment' => 'pcKindpayment',
        'asked_number' => 'pcKindaskedNumber',
        'sent_number' => 'pcKindsentNumber',
        _ => 'pcKindphone',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, scrolledUnderElevation: 0, title: Text(tr(context, 'apTitle'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: FutureBuilder<List<MyStrike>>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
            final list = snap.data;
            if (list == null) return const Center(child: CircularProgressIndicator());
            if (list.isEmpty) return EmptyState(icon: Icons.verified_outlined, title: tr(context, 'apNone'));
            final now = ServerClock.now();
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(trf(context, 'apIntro', {'d': 14}), style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              for (final s in list)
                AppCard(
                  key: ValueKey('strike_${s.id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(context, _kind(s.kind)), style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (s.at != null) Text(formatDateTime(s.at!), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    if (s.excerpt.isNotEmpty) Text('“${s.excerpt}”', style: TextStyle(color: AppColors.faint, fontSize: 12)),
                    const SizedBox(height: 6),
                    if (s.appeal != null)
                      Text(tr(context, 'apStatus_${s.appeal!.status}') + (s.appeal!.note.isEmpty ? '' : ': ${s.appeal!.note}'), key: ValueKey('apStatus_${s.id}'), style: TextStyle(fontWeight: FontWeight.w700, color: s.appeal!.status == 'granted' ? AppColors.success : s.appeal!.status == 'rejected' ? AppColors.warning : AppColors.muted))
                    else if (s.canAppeal(now))
                      OutlinedButton(key: ValueKey('apAppeal_${s.id}'), onPressed: () => _appeal(s), child: Text(tr(context, 'apAppeal')))
                    else
                      Text(tr(context, 'apClosed'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
                  ]),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

class _AppealDialog extends StatefulWidget {
  const _AppealDialog();

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'apAppeal')),
      content: TextField(key: const ValueKey('apText'), controller: _text, maxLength: StrikeAppealService.maxText, maxLines: 4, autofocus: true, decoration: InputDecoration(labelText: tr(context, 'apWhy'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
        FilledButton(key: const ValueKey('apSend'), onPressed: () => Navigator.pop(context, _text.text), child: Text(tr(context, 'apSendBtn'))),
      ],
    );
  }
}
